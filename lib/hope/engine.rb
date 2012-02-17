module Hope
  
  def self.engines
    @engines ||= {}
  end
  
  def self.register_engine eng
    self.engines[eng.uri] = eng
  end
  
  def self.unregister_engine eng
    self.engines.delete eng.uri
  end
  
  class RpcHandler
    def on_readable(socket, messages)
      
    end
  end
  
  class Engine
    
    java_import com.espertech.esper.client.EPServiceProviderManager
    java_import com.espertech.esper.client.Configuration
    
    attr_reader :provider, :uri, :deployments
    
    def self.get uri=nil
      Hope.engines[uri]
    end
    
    def self.all
      EPServiceProviderManager.getProviderURIs.to_a
    end
    
    def initialize uri=nil, config_file=nil
      puts "Init engine #{uri} with config: #{config_file}"
      @uri = uri || "default"
      Hope.register_engine(self)
      @configuration = Configuration.new
      if config_file
        if File.exists?(config_file)
          @configuration.configure(config_file)
        else
          puts "I cant find this config file: #{config_file}"
        end
      end
      
      provider
      
      #@rpc = Hope.ctx.connect ZMQ::REP, "ipc://hope-rpc", self
      @sub = Hope.ctx.connect ZMQ::SUB, "ipc://hope-in", self
      @sub.subscribe ""

      @pub = Hope.ctx.connect ZMQ::PUB, "ipc://hope-out"
      @deployments = {}
      @received = 0
    end
    
    def on_readable(socket, messages)
      @received += 1
      msg = messages.first.copy_out_string
      event = JSON.parse(msg)
      puts "[##{@received}]: #{event.inspect}"
      self.sendEvent(event, event['type'])
    end    
    
    # Deployment API
    
    def epl_stream epl_file
      com.espertech.esper.client.EPServiceProviderManager.java_class.class_loader.getResourceAsStream(epl_file)
    end
    
    def deployment_info did
      admin.getDeploymentAdmin.getDeployment did
    end
    
    def deploy epl_file
      begin
        stream = epl_stream(epl_file)
        return false unless stream
        module_uri = epl_file.gsub(/\.epl$/, '')
        puts "Deploying module #{module_uri}..."
        undeploy_module(module_uri)
        res = admin.getDeploymentAdmin.readDeploy(stream, module_uri, nil, nil)
        puts "DeploymentResult: #{res.toString}"
        if res
          res.getStatements.each do |s|
            s.addListener Hope::Pub.new(s.getName, @pub)
          end
        end
        @deployments[module_uri] = res
      rescue => err
        puts "Deployment failed: #{err}"
        return false
      end
    end
    
    def undeploy_module module_uri
      d = @deployments[module_uri]
      return false unless d
      undeploy d.getDeploymentId, true
    end
    
    def undeploy did, remove=true
      return false unless deployment_info(did)
      puts "Undeploy: #{did}"
      if remove
        admin.getDeploymentAdmin.undeployRemove did
      else
        admin.getDeploymentAdmin.undeploy did
      end
    end

    # Provider API
    def provider
      if uri.nil?
        @provider ||= EPServiceProviderManager.getDefaultProvider(@configuration)
      else
        @provider ||= EPServiceProviderManager.getProvider(uri, @configuration)
      end
    end
    
    def destroy
      unless provider.destroyed?
        provider.destroy
        Hope.unregister_engine(self)
      end
    end

    def destroyed?
      provider.destroyed?
    end
    
    def reset
      # @subscriptions.each { |sub| self.unsubscribe(sub) }
      statements.map do |st|
        st.remove_all_listeners
        st.destroy
      end
    end
    
    # Admin API
    def admin
      provider.getEPAdministrator
    end
    
    def statement_names
      admin.getStatementNames.to_a
    end
    
    def statements
      statement_names.map { |n| Hope::Statement.new(admin.getStatement(n)) } 
    end
    
    def statement stmt_name
      s = admin.getStatement stmt_name
      Statement.new(s) unless s.nil?
    end
    
    def add_epl epl, name=nil
      name = nil if name.blank?
      Hope::Statement.new admin.createEPL(epl, name)
    end
    
    def add_pattern pattern, name=nil
      name = nil if name.blank?
      Hope::Statement.new admin.createPattern(pattern, name)
    end
    
    def add_event_type event_type
      return if @registered_types[event_type.name]
      @registered_types[event_type.name] = event_type.schema
      add_epl(event_type.schema)
    end
    
    def stop
      admin.stopAllStatements
    end
    
    def start
      admin.startAllStatements
    end
    
    # Runtime API
    def runtime
      provider.getEPRuntime
    end
    
    def sendEvent(e, type=nil)
      begin
        if type
          runtime.sendEvent(e, type)
        else
          runtime.sendEvent(e)
        end
      rescue => err
        puts "\n\n\n\n\n\n----------------------------\nEngine Error: #{err}"
        puts "Error sending Event[#{type}]=#{e.inspect}"
        puts "Backtrace: \n#{err.backtrace.join("\n>")}"
        puts "-----------------------------\n\n\n\n"
      end
    end
    
    # Misc
    def serializable_hash
      {
        :id => uri,
        :received       => @received,
        :statements     => statements.map(&:serializable_hash),
        :subscriptions  => @subscriptions,
        :deployments    => deployments
      }
    end
    
    def to_json
      serializable_hash.to_json
    end
  end
  
end