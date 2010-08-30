class String
  def strip_trailing_punctuation
    self.sub(/[.;\/]\s*$/,'')
  end
end

class MARCDocument < Ferret::Document

  def format_field(field, separator=' ', include_codes=[]) 
    return nil unless field

    parts = []
    field.each do |subfield|
      if include_codes.empty? or include_codes.index(subfield.code)
        parts << subfield.value
      end
    end
    parts.join(separator).strip_trailing_punctuation
  end


  def date_modified(marc) 
    DateTime.parse(marc['005'].value)
  end

  def lcc(marc)
    lccs = []
    lcc_fields = marc.find_all{|f| f.tag == "053"}
    lcc_fields.each do | f |
      lccs << format_field(f, nil, ['a'])
    end
    lcc_fields
  end

  def normalize_lccn(marc)
    lccn = marc['010']['a']
    lccn.gsub(/\s/,'')
  end

  def format_subdivisions(f)
    format_field(f, '--', ['v', 'x', 'y', 'z'])
  end

  def format_personal_field(f)
    main = format_field(f, ' ', ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't'])
    sub = format_subdivisions(f)
    if(sub.empty?)
      return main
    end
    "#{main}--#{sub}"
  end

  def format_corporate_field(f)
    main = format_field(f, ' ',  ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'l', 'm', 'n', 'o', 'p', 'r', 's', 't'])
    sub = format_subdivisions(f)
    if(sub.empty?)
      return main
    end
    "#{main}--#{sub}"
  end  

  def format_meeting_field(f)
    main = format_field(f, ' ', ['a', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'n', 'p', 'q', 's', 't'])
    sub = format_subdivisions(f)
    if(sub.empty?)
      return main
    end
    "#{main}--#{sub}"
  end

  def format_title_field(f)
    main = format_field(f, ' ', ['a', 'd', 'f', 'g', 'h', 'i', 'k', 'l', 'm', 'n', 'o', 'p', 'r', 's', 't'])
    sub = format_subdivisions(f)
    if(sub.empty?)
      return main
    end
    "#{main}--#{sub}"
  end

  def format_chronological_field(f)
    main = format_field(f, ' ', ['a', 'i'])
    sub = format_subdivisions(f)
    if(sub.empty?)
      return main
    end
    "#{main}--#{sub}"
  end
  
  def format_topical_field(f)
    main = format_field(f, ' ', ['a', 'b'])
    sub = format_subdivisions(f)
    if(sub.empty?)
      return main
    end
    "#{main}--#{sub}"
  end

  def format_geographic_field(f)
    main = format_field(f, ' ', ['a'])
    sub = format_subdivisions(f)
    if(sub.empty?)
      return main
    end
    "#{main}--#{sub}"
  end

  def format_genre_field(f)
    format_geographic_field(f)
  end

  def format_general_subd_field(f)
    format_subdivisions(f)
  end

  def format_geographic_subd_field(f)
    format_subdivisions(f)
  end
  def format_chronological_subd_field(f)
    format_subdivisions(f)
  end
  def format_form_subd_field(f)
    format_subdivisions(f)
  end

  def subdivision_strings(f)  
    subd_codes = ['v','x','y','z']
    f.each do |sub|
      if subd_codes.index(sub.code)
        if self["#{sub.code}_str".to_sym]
          self["#{sub.code}_str".to_sym] = [*self["#{sub.code}_str".to_sym]]
          self["#{sub.code}_str".to_sym] << sub.value
        else
          self["#{sub.code}_str".to_sym] = sub.value
        end
      end
    end
  end

  def format_personal_name(f)
    self[:label] = format_personal_field(f)
    self[:top_term_str] = format_field(f, ' ', ['a', 'b', 'c', 'd', 'q'])
    subdivision_strings(f)
  end

  def format_corporate_name(f)
    self[:label] = format_corporate_field(f)
    self[:top_term_str] = format_field(f, ' ', ['a', 'b', 'c', 'd'])
    subdivision_strings(f)
  end

  def format_meeting(f)
    self[:label] = format_meeting_field(f)
    subdivision_strings(f)
  end

  def format_uniform_title(f)
    self[:label] = format_title_field(f)
    self[:top_term_str] = format_field(f, ' ',['a', 'd', 'f', 'g', 'n', 'o', 'p', 'r', 's', 't'])
    subdivision_strings(f)
  end

  def format_chronological_term(f)
    self[:label] = format_chronological_field(f)
    subdivision_strings(f)
  end  

  def format_topical_term(f)
    self[:label] = format_chronological_field(f)
    self[:top_term_str] = format_field(f, ' ', ['a', 'b'])
    subdivision_strings(f)
  end

  def format_geographical_name(f)  
    self[:label] = format_geographic_field(f)
    self[:top_term_str] = format_field(f, ' ', ['a'])
    subdivision_strings(f)
  end

  def format_genre_term(f)
    self[:label] = format_genre_field(f)
    self[:top_term_str] = format_field(f, ' ', ['a'])
    subdivision_strings(f)
  end

  def format_general_subdivision(f)
    self[:label] = format_general_subd_field(f)
    subdivision_strings(f)
  end  

  def format_geographic_subdivision(f)
    self[:label] = format_geographic_subd_field(f)
    subdivision_strings(f)
  end  

  def format_chronological_subdivision(f)
    self[:label] = format_chronological_subd_field(f)
    subdivision_strings(f)
  end  

  def format_form_subdivision(f)
    self[:label] = format_form_subd_field(f)
    subdivision_strings(f)
  end  

  def get_alt_labels(marc)
    alt_labels = []
    alts = marc.find_all {|f| f.tag =~ /^4../}
    alts.each do | a |
      alt_labels << case a.tag
      when "400" then format_personal_field(a)
      when "410" then format_corporate_field(a)
      when "411" then format_meeting_field(a)
      when "430" then format_title_field(a)
      when "448" then format_chronological_field(a)
      when "450" then format_topical_field(a)
      when "451" then format_geographic_field(a)
      when "455" then format_genre_field(a)
      when "480" then format_general_subd_field(a)
      when "481" then format_geographic_subd_field(a)
      when "482" then format_chronological_subd_field(a)
      when "485" then format_form_subd_field(a)
      end
    end
    alt_labels
  end

  def related_terms(marc)
    tracings = {:broader_str=>[], :narrower_str=>[], :related_str=>[]}
    fields = marc.find_all{|f| f.tag =~ /^5../}
    fields.each do | field |
      term = case field.tag
      when "500" then format_personal_field(field)
      when "510" then format_corporate_field(field)
      when "511" then format_meeting_field(field)
      when "530" then format_title_field(field)
      when "548" then format_chronological_field(field)
      when "550" then format_topical_field(field)
      when "551" then format_geographic_field(field)
      when "555" then format_genre_field(field)
      when "580" then format_general_subd_field(field)
      when "581" then format_geographic_subd_field(field)
      when "582" then format_chronological_subd_field(field)
      when "585" then format_form_subd_field(field)
      end
      w = field['w']
      case w
      when 'g' then tracings[:broader_str] << term
      when 'h' then tracings[:narrower_str] << term
      else tracings[:related_str] << term
      end
    end
    tracings.each_pair do |k, v|
      unless v.empty?
        self[k] = v
      end
    end
  end  

  def initialize(marc)
    super()
    self[:lccn] = normalize_lccn(marc)
    self[:lcc] = lcc(marc)
    self[:marc_last_modified] = date_modified(marc)
    self[:heading_type] = case
    when marc['100']
      format_personal_name(marc['100'])
      "Personal Name"
    when marc['110']
      format_corporate_name(marc['110'])
      "Corporate Name"
    when marc['111']
      format_meeting(marc['111'])
      "Meeting"
    when marc['130']
      format_uniform_title(marc['130'])
      "Uniform Title"
    when marc['148']
      format_chronological_term(marc['148'])
      "Chronological Term"
    when marc['150']
      format_topical_term(marc['150'])
      "Topical Term"
    when marc['151']
      format_geographical_name(marc['151'])    
      "Geographical Name"
    when marc['155']
      format_genre_term(marc['155'])        
      "Genre/Form Term"
    when marc['180']
      format_general_subdivision(marc['180'])    
      "General Subdivision"
    when marc['181']
      format_geographic_subdivision(marc['181'])  
      "Geographic Subdivision"
    when marc['182'] 
      format_chronological_subdivision(marc['182'])
      "Chronological Subdivision"
    when marc['185']
      format_form_subdivision(marc['185'])  
      "Form Subdivision"
    end
    self[:label_str] = self[:label]
    self[:alt_labels] = get_alt_labels(marc)
    self[:alt_labels_str] = self[:alt_labels]
    related_terms(marc)
    self[:marc_record] = marc.to_marc
    self[:last_modified] = DateTime.now
  end

end