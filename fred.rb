$KCODE = 'u'
require 'rubygems'
require 'jcode'
require 'ferret'
require 'marc'
require 'sinatra'
require 'cgi'
require 'yaml'
require 'open-uri'
require 'haml'
require 'lib/marc_document'
require 'lib/marc_hash'
require 'json'
require 'builder'

require 'rack/conneg'
require 'rack/flash'
configure do
  config = YAML.load_file("./config.yml")
  set :config, config
  set :db, Ferret::Index::Index.new(config['ferret']['config'])
  #set :haml, {:encoding=>"utf-8"}
end

use(Rack::Conneg) { |conneg|
  Rack::Mime::MIME_TYPES['.mrc'] = 'application/marc'
  Rack::Mime::MIME_TYPES['.marcxml'] = 'application/marc21+xml'     
  Rack::Mime::MIME_TYPES['.osdx'] = 'application/opensearchdescription+xml'
  conneg.set :accept_all_extensions, false
  conneg.set :fallback, :html
  conneg.ignore('/public/')
  conneg.ignore('/stylesheets/')
  conneg.provide([:html, :rdf, :mrc, :marcxml, :json, :atom, :osdx])
}

before do
  if negotiated?
    content_type negotiated_type
  end
end

get '/' do
  haml :index
end

get '/lccn/:id' do
  @record = nil
  options.db.search_each("lccn:#{params["id"]}") do |id, score|
    @record = options.db[id]
  end
  #unless @record[:last_checked_date] && (DateTime.parse(@record[:last_checked_date]) > (DateTime.now() - 30))
  #  check_for_update(@record)
  #end
  @record[:marc] = parse_marc(@record[:marc_record])
  respond_to do | wants |
    #wants.rdf { @subject.to_xml() }
    wants.marcxml { @record[:marc].to_xml.to_s}
    wants.mrc { @record[:marc].to_marc }
    wants.html { haml :record }
    wants.json { @record[:marc].to_hash.to_json }
  end
end

get '/browse/*' do
  i = 0
  @terms = []
  trm = nil
  params[:splat].each do |splat|
    trm = splat unless splat.empty?
  end
  if trm
    term_enum = options.db.reader.terms_from(:label_str, trm)
  else
    term_enum = options.db.reader.terms(:label_str)
  end
  term_enum.each do |term, count| 
    options.db.reader.term_docs_for(:label_str, term).each do |doc_id,freq|
      @terms << options.db[doc_id]
    end
    i+= 1
    break if i == 25
  end
  @prev = nil
  @prev = previous(term_enum, @terms.first[:label], 25) if trm
  respond_to do |wants|
    wants.html { haml :browse }
  end
end

get '/group/:term' do
  @terms = term_cluster(params[:term])
  respond_to do |wants|
    wants.marcxml { array_to_marcxml(@terms) }
    wants.mrc { array_to_marc(@terms) }
    wants.html { haml :group }
    wants.json { array_to_marcjson(@terms) }
  end  
end

get '/label/:term' do
  phrase = Ferret::Search::PhraseQuery.new(:label_str)
  phrase.add_term(params[:term])
  options.db.search_each(phrase) do |id, score|
    redirect "/lccn/#{options.db[id][:lccn]}"
  end
  redirect "/search?query=#{params[:term]}"
end

get '/feed' do
  @results = []
  @offset = (params["offset"]||0).to_i
  @total = options.db.search_each(Ferret::Search::MatchAllQuery.new, {:offset=>@offset, :limit=>25, :sort=>"last_modified DESC"}) do |id, score|
    @results << options.db[id]
  end
  respond_to do | wants |
    wants.atom {
      @results.each {|term| term[:marc]=parse_marc(term[:marc_record])}
      haml :opensearch
    }  
  end 
end 

get '/search' do
  adv_params = advanced_params
  query = generate_query_object(adv_params)
  @results = []
  @offset = (params["offset"]||0).to_i
  @total = options.db.search_each(query, {:offset=>@offset, :limit=>25}) do |id, score|
    @results << options.db[id]
  end

  respond_to do |wants|
    wants.html { 
      if @total <= options.config['facets'][:threshold]
        @facets = generate_facets(query)
      else
        @facets = type_facets(adv_params)
      end      
      haml :search
    }
    wants.atom {
      @results.each {|term| term[:marc]=parse_marc(term[:marc_record])}
      haml :opensearch
    }
    wants.osdx {
      haml :opensearchdescription
    }
  end
end

helpers do
  def parse_marc(marc)
    MARC::Record.new_from_marc(marc)
  end
  
  def term_cluster(top_term)
    docs = []
    term = Ferret::Search::TermQuery.new(:top_term_str, top_term)
    options.db.search_each(term, {:limit=>:all, :sort=>"label_str"}) do |id, score|
      docs << options.db[id]
    end
    docs
  end
  
  def browse_from_here(label)
    i = 0
    terms = []
    previous(options.db.reader.terms(:label_str), label, 5).each do |t|
      options.db.reader.term_docs_for(:label_str, t).each do |doc_id, freq|
        terms << options.db[doc_id]
      end
    end
    options.db.reader.terms_from(:label_str, label).each do |term,count|
      options.db.reader.term_docs_for(:label_str, term).each do |doc_id,freq|
        terms << options.db[doc_id]
      end      
      i+=1
      break if i==5
    end
    terms
  end
  
  
  def previous(term_enum, term, num)
    term_enum.skip_to((term[0]-1).chr)    
    term_list = []
    term_enum.each do |t,f|
      return term_list if term == t
      term_list.shift if term_list.length > (num-1)
      term_list << t
    end    
    term_list
  end
  
  def generate_query_object(params)
    query = Ferret::Search::BooleanQuery.new
    base = case
    when params["query"] && !params["query"].empty?
      parser = Ferret::QueryParser.new
      parser.fields = options.db.reader.tokenized_fields
      parser.parse(params["query"][0])
    else
      Ferret::Search::MatchAllQuery.new
    end
    query.add_query(base, :must)
    {:x=>:x_str, :y=>:y_str, :v=>:v_str, :z=>:z_str, :type=>:heading_type}.each_pair do |filter,index|
      next unless params[filter.to_s]
      [*params[filter.to_s]].each do | f |
        phrase = Ferret::Search::PhraseQuery.new(index)
        phrase.add_term(f)
        query.add_query(phrase, :must)
      end
    end
    query
  end
  
  def generate_facets(query)
    s = options.db.search(query, {:limit=>1, :filter_proc=>filter_proc})
    return @facet_fields
  end
  
  def type_facets(params)
    types = []
    facets = {}
    type_terms = options.db.reader.terms(:heading_type)
    searcher = Ferret::Search::Searcher.new(options.db.reader)
    type_terms.each do | term, frq |
      if params["type"]
        types << term unless params["type"].index(term)
      else
        types << term
      end
    end
    types.each do |type|
      facet_query = generate_query_object(params)
      phrase = Ferret::Search::PhraseQuery.new(:heading_type)
      phrase.add_term(type)
      facet_query.add_query(phrase, :must)
      top = searcher.search(facet_query, :limit=>1)
      if top.total_hits > 0
        facets[type] = top.total_hits
      end
    end
    return {:heading_type=>facets}
  end
  
  def generate_query_string(extra_params, remove_offset=true)
    query_parts = []
    advanced_params.each_pair do |key,vals|
      vals.each do |val|
        next if remove_offset && key == "offset"
        query_parts << "#{key}=#{val}"
      end
    end
    special_keys = {:x_str=>:x, :y_str=>:y, :v_str=>:v, :z_str=>:z, :heading_type=>:type}
    extra_params.each_pair do |key,vals|
      [*vals].each do |val|
        next unless val
        if special_keys[key]
          key = special_keys[key]
        end
        query_parts << "#{key}=#{val}"
      end
    end
    query_parts.join("&")
  end
  
  def generate_offset_query(offset)
    query_parts = []
    offset_inc = false
    advanced_params.each_pair do |key,vals|
      vals.each do |val|
        if key == "offset"
          query_parts << "#{key}=#{offset}"
          offset_inc = true
        else
          query_parts << "#{key}=#{val}"
        end        
      end
    end
    query_parts << "offset=#{offset}" unless offset_inc      
    query_parts.join("&")
  end    
  
  def filter_proc
    @facet_fields = {}
    options.config["facets"][:fields].each do |field|
      @facet_fields[field] = {}
    end
    fp = lambda do |doc_id,score,searcher|
      doc = searcher[doc_id]
      (doc.fields&@facet_fields.keys).each do |key|
        [*doc[key]].each do |v|
          next unless v
          @facet_fields[key][v] ||=0
          @facet_fields[key][v] += 1        
        end
      end
    end
    fp
  end
  
  def advanced_params
    query_params = request.env["rack.input"].read
    if query_params.empty?
      query_params = request.env["rack.request.query_string"]
    end
    CGI.parse(query_params)
  end 
  
  def check_for_update(record)
    if record[:lccn] =~ /^n/
      uri = nil
      unless record[:heading_type] == "Uniform Title" or record[:lccn] =~ /^nb/
        uri = "http://errol.oclc.org/laf/#{record[:lccn]}.MarcXML"
      end
    else
      uri = "http://tspilot.oclc.org/lcsh/#{record[:lccn]}.marcxml"
    end
    return false unless uri
    response = open(uri)
    if response
      begin
        marc = MARC::XMLReader.new(response)
        marc_record = nil
        marc.each do |m|
          marc_record = m
        end        
        return false unless marc_record
      rescue
        return false
      end
      
      doc = MARCDocument.new(marc_record)      
    end
    
    
  end
  
  def paginate(total, offset)
    items_per_page = 25
    total_pages = total.divmod(items_per_page)[0]
    return nil if total_pages < 1
    ranges = []
    if total_pages > 10        
      if offset != (5*items_per_page)
        ranges << (0..4)
      end
      if offset == (5*items_per_page)
        ranges << (5..6)
      else
        ranges << '...'
      end
      start = nil
      endpoint = nil
      if offset > (5*items_per_page)
        start = (offset-items_per_page)/items_per_page
        if (offset/items_per_page) == total_pages
          endpoint = total_pages
        else
          endpoint = (offset+items_per_page)/items_per_page
        end
        ranges << (start..endpoint)
      end
      if !endpoint || endpoint < total_pages
        bottom = (total_pages-4)
        rng = (bottom..total_pages)
        while rng.include?(endpoint)
          bottom += 1
          rng = (bottom..total_pages)
        end
        ranges << rng
      end
    else
      ranges << (0..total_pages)
    end
    ranges
  end    
  
  def format_facets
    facets = []
    options.config["facets"][:fields].each do |field|
      next if !@facets[field] || @facets[field].empty?
      f = {field => @facets[field].sort{|a,b| b[1]<=>a[1]}}
      f[field].flatten!
      facets << f
    end         
    facets
  end 
  
  def array_to_marcxml(docs)
    out = StringIO.new
    writer = MARC::XMLWriter.new(out)
    doc.each do |doc|
      writer.write(doc[:marc])
    end
    out.rewind
    out.read
  end
  def array_to_marc(docs)
    out = StringIO.new
    writer = MARC::Writer.new(out)
    doc.each do |doc|
      writer.write(doc[:marc])
    end
    out.rewind
    out.read
  end
  
  def array_to_marcjson(doc)
    out = []
    doc.each do |doc|
      out << doc[:marc].to_hash
    end
    out.to_json
  end
end

class String
  def escape_search
    self.gsub(/([":()\[\]{}!+~^\-\|<>=\*\?\\])/, '\\\\\1')
  end
  
  def escape_browse
    self.gsub(/("")/, '\\\\\1')    
  end
end
    