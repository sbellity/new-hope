include_class 'com.espertech.esper.client.UpdateListener'


module Hope 
  class Pub
    
    include UpdateListener    
    
    attr_reader :received
    
    def initialize name, pub, opts={}
      @name = name
      @received = { :success => 0, :errors => 0, :latest_error => "" }
      @pub = pub
    end
    
    def update(newEvents, oldEvents)
      events = { :new_events => pack_events(newEvents), :old_events => pack_events(oldEvents), :name => @name }
      puts "Publishing new_events: #{events.inspect}"
      @pub.send_msg '', events.to_json
    end
    
    def pack_events events
      ret = []
      events.each do |event_bean|
        event = event_bean.getUnderlying
        event_properties = event_bean.getEventType.getPropertyNames.map &:to_s
        unless event.is_a?(Java::JavaUtil::HashMap) || event.is_a?(Hash)
          event = event_properties.inject({}) { |evd,k| evd.merge k => event_bean.getUnderlying.send(k.to_sym) }
        end
        event = event.to_hash
        ret << {
          :event_type       => event_bean.getEventType.getName,
          :event_properties => event_properties,
          :event            => event
        }
      end unless events.nil?
      ret
    end
        
  end
end