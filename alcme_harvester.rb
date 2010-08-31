$KCODE = 'u'
require 'rubygems'
require 'ferret'
require 'sru'
require 'marc'
require 'lib/marc_document'

def retrieve_records(client, query, start)
  client.search_retrieve(query, {:maximumRecords=>100, :recordSchema=>'info:srw/schema/1/marcxml-v1.1', :startRecord=>start})
end

def write_records(writer, response)
  i = 0
  response.each do | r |
    MARC::XMLReader.new(StringIO.new(r.to_s)).each do |marc|
      writer.write(marc)
    end
    i+=1
  end  
  return i
end

base_query = "oai.datestamp >= '2006-12-12'"
start = (ARGV[0] || 1).to_i
client = SRU::Client.new('http://alcme.oclc.org/srw/search/lcnaf/', :parser=>"libxml")
writer = MARC::Writer.new('/Volumes/External/shared/PermaFred/alcme_bulk.mrc')
response = retrieve_records(client,base_query,start)
total = response.number_of_records
result_set = nil
result_set_elem = response.doc.find_first("//zs:resultSetId", response.namespaces)
if result_set_elem
  result_set = result_set_elem.inner_xml 
  query = "cql.resultSetId = #{result_set}"
else
  query = base_query
end

start += write_records(writer, response)

while start < total
  response = retrieve_records(client,query,start)
  result_set = nil
  result_set_elem = response.doc.find_first("//zs:resultSetId", response.namespaces)
  if result_set_elem
    result_set = result_set_elem.inner_xml 
    query = "cql.resultSetId = #{result_set}"
  else
    query = base_query
  end
  start += write_records(writer, response)
  puts start
end  

writer.close




