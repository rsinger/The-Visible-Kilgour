require 'marc'

module MARC
  class Record
    # Returns a (roundtrippable) hash representation
    def to_hash
      record_hash = {'leader'=>self.leader, 'fields'=>[]}
      self.fields.each do |field|
        record_hash['fields'] << field.to_hash
      end
      record_hash
    end 
  end
  
  class ControlField
    def to_hash
      return {self.tag=>self.value}
    end
  end
  
  class DataField
    def to_hash
      field_hash = {self.tag=>{'ind1'=>self.indicator1,'ind2'=>self.indicator2,'subfields'=>[]}}
      self.each do |subfield|
        field_hash[self.tag]['subfields'] << {subfield.code=>subfield.value}
      end
      field_hash
    end
  end
end