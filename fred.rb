require 'rubygems'
require 'ferret'
require 'marc'
require 'sinatra'
require 'cgi'
require 'yaml'

require 'rack/conneg'
require 'rack/flash'
configure do
  config = YAML.load_file("./config.yml")
  set :config, config
  set :db, Ferret::Index::Index.new(config['ferret']['config'])
end

use(Rack::Conneg) { |conneg|
  Rack::Mime::MIME_TYPES['.mrc'] = 'application/marc'
  Rack::Mime::MIME_TYPES['.marcxml'] = 'application/marc21+xml'     
  conneg.set :accept_all_extensions, false
  conneg.set :fallback, :html
  conneg.ignore('/public/')
  conneg.ignore('/stylesheets/')
  conneg.provide([:html, :rdf, :mrc, :marcxml, :json])
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
  @record[:marc] = parse_marc(@record[:marc_record])
  respond_to do | wants |
    #wants.rdf { @subject.to_xml() }
    wants.marcxml { @record[:marc].to_xml.to_s}
    wants.mrc { @record[:marc].to_marc }
    wants.html { haml :record }
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
    term_enum = options.db.reader.terms_from(:label, trm)
  else
    term_enum = options.db.reader.terms(:label)
  end
  term_enum.each do |term, count| 
    options.db.reader.term_docs_for(:label, term).each do |doc_id,freq|
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
    wants.html { haml :group }
  end  
end

get '/label/:term' do
  phrase = Ferret::Search::PhraseQuery.new(:label_str)
  phrase.add_term(params[:term])
  options.db.search_each(phrase) do |id, score|
    redirect "/lccn/#{options.db[id][:lccn]}"
  end
  redirect "/search/?query=#{params[:term]}"
end

get '/search/' do
  adv_params = advanced_params
  query = generate_query_object(adv_params)
  @results = []
  @offset = (params["offset"]||0).to_i
  @total = options.db.search_each(query, {:offset=>@offset, :limit=>25}) do |id, score|
    @results << options.db[id]
  end
  #if @total < 10000
  #  @facets = generate_facets(query, adv_params)
  #else
    @facets = type_facets(adv_params)
  #end
  respond_to do |wants|
    wants.html { haml :search }
  end
end

helpers do
  def parse_marc(marc)
    MARC::Record.new_from_marc(marc)
  end
  
  def term_cluster(top_term)
    docs = []
    term = Ferret::Search::TermQuery.new(:top_term_str, top_term)
    options.db.search_each(term, {:limit=>:all, :sort=>"label DESC"}) do |id, score|
      docs << options.db[id]
    end
    docs.reverse
  end
  
  def browse_from_here(label)
    i = 0
    terms = []
    previous(options.db.reader.terms(:label), label, 5).each do |t|
      options.db.reader.term_docs_for(:label, t).each do |doc_id, freq|
        terms << options.db[doc_id]
      end
    end
    options.db.reader.terms_from(:label, label).each do |term,count|
      options.db.reader.term_docs_for(:label, term).each do |doc_id,freq|
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
    {:x=>:x_str, :y=>:y_str, :v=>:v_str, :w=>:w_str, :type=>:heading_type}.each_pair do |filter,index|
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
    return {:type=>facets}
  end
  
  def generate_query_string(extra_params, remove_offset=true)
    query_parts = []
    advanced_params.each_pair do |key,vals|
      vals.each do |val|
        next if remove_offset && key == "offset"
        query_parts << "#{key}=#{val}"
      end
    end
    extra_params.each_pair do |key,vals|
      [*vals].each do |val|
        next unless val
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
  
  def filter_proc(params)
    @facet_fields = {}
    
    @filter_proc = lambda do |doc,score,searcher|
      @facet_fields.keys.each do |field|
        [*searcher[doc][field]].each do |term|  
          next if term.nil?
          @facet_fields[field][term] ||=0
          @facet_fields[field][term] += 1
        end
      end
    end
  end
  
  def advanced_params
    query_params = request.env["rack.input"].read
    if query_params.empty?
      query_params = request.env["rack.request.query_string"]
    end
    CGI.parse(query_params)
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
end

class String
  def escape_search
    self.gsub(/([":()\[\]{}!+~^\-\|<>=\*\?\\])/, '\\\\\1')
  end
  
  def escape_browse
    self.gsub(/("")/, '\\\\\1')    
  end
end
    