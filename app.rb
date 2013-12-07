require File.expand_path '../lib/cocoapods.org', __FILE__

# This app shows how to integrate the Picky server directly
# inside a web app. However, if you really need performance
# and easy caching this is not recommended.
#
class CocoapodSearch < Sinatra::Application
  
  # Data container and search.
  #
  pods = Pods.new Pathname.new ENV['COCOAPODS_SPECS_PATH'] || './tmp/specs'
  search = Search.new pods
  
  self.class.send :define_method, :prepare do |force = false|
    pods.prepare force
    search.reindex
  end
  
  set :logging,       false
  set :static,        true
  set :public_folder, File.dirname(__FILE__)
  set :views,         File.expand_path('../views', __FILE__)

  # Root, the search page.
  #
  # TODO Remove as soon as the new cocoapods.org goes live on that address.
  #
  get '/' do
    redirect "http://beta.cocoapods.org?q=#{params[:q]}", 'Deprecating current CocoaPods.org'
    
    @query = params[:q]
    @platform = Platform.extract_from @query
    
    haml :index, :layout => :search
  end

  # Returns picky style results specific to cocoapods.org.
  #
  # You get the results from the (local) picky server and then
  # populate the result hash with rendered models.
  #
  get '/search' do
    results = search.interface.search params[:query], params[:ids] || 20, params[:offset] || 0
    results = results.to_hash
    results.extend Picky::Convenience
    results.populate_with Pod::View do |pod|
      pod.to_html
    end
    Yajl::Encoder.encode results
  end
  
  # Returns picky style results specific to cocoapods.org.
  #
  # TODO Remove.
  #
  get '/search.json' do
    response["Access-Control-Allow-Origin"] = "*"
    
    results = search.interface.search params[:query], params[:ids] || 20, params[:offset] || 0
    results = results.to_hash
    results.extend Picky::Convenience
    results.populate_with Pod::View do |pod|
      pod.to_hash
    end
    Yajl::Encoder.encode results
  end
  
  # Returns a JSON hash with helpful content with "no results" specific to cocoapods.org.
  #
  get '/no_results.json' do
    response["Access-Control-Allow-Origin"] = "*"
    
    query = params[:query]
    
    suggestions = {
      tag: search.index.facets(:tags)
    }
    
    if query
      split = search.splitter.split query
      result = search.interface.search split.join(' '), 0, 0
      suggestions[:split] = [split, result.total]
    end
    
    Yajl::Encoder.encode suggestions
  end

  # Get and post hooks for triggering updates.
  #
  [:get, :post].each do |type|
    send type, "/post-receive-hook/#{ENV['HOOK_PATH']}" do
      begin
        self.class.prepare true

        status 200
        body "REINDEXED"
      rescue StandardError => e
        status 500
        body e.message
      end
    end
  end
  
  # Pod API code.
  #
  # TODO Remove -> Trunk will handle this.
  #
  get '/api/v1/pod/:name.json' do
    pod = pods.specs[params[:name]]
    pod && pod.to_hash.to_json || status(404) && body("Pod not found.")
  end
  
  # Pod API code.
  #
  # TODO Remove -> Trunk will handle this.
  #
  get '/pod/:name' do
    pod = pods.specs[params[:name]]
    if pod
      @infos = pod.to_hash
      name = @infos['name']
      authors = @infos['authors']
      
      # Search for authors' other pods.
      #
      @authors = {}
      authors = if authors.respond_to? :keys
        authors.keys
      else
        [authors]
      end
      authors.each do |name|
        names = name.split
        results = search.interface.search names.map { |name| "author:#{name}" }.join(' ')
        @authors[name] = results.ids
      end
      
      # Get topic from pod and search for that topic.
      #
      @tags = {}
      tags = Pod::View.content[name].tags
      tags.each do |name|
        names = name.split
        results = search.interface.search names.map { |name| "tag:#{name}" }.join(' ')
        @tags[name] = results.ids
      end
      
      haml :pod, :layout => :search
    else
      status(404)
      body("Pod not found.")
    end
  end

  # Temporary for CocoaDocs till we separate out API & html 
  #
  # TODO Remove.
  #
  get '/api/v1.5/pods/search' do
    results = search.interface.search params[:query], params[:ids] || 20, params[:offset] || 0
    results = results.to_hash
    results.extend Picky::Convenience
    
    simple_data = []
    results.populate_with Pod::View do |pod|
      simple_data << pod.render_short_json
    end
    
    response["Access-Control-Allow-Origin"] = "*"
    
    Yajl::Encoder.encode simple_data
  end

  # API 2.0
  #
  
  # Returns a Picky style JSON result with entries rendered as a JSON hash.
  #
  get '/api/v2.0/pods/search/picky.json' do
    cors_allow_all
    
    picky_result search, params do |pod|
      pod.to_hash
    end
  end
  
  # Returns a flat list of results with entries rendered as a JSON hash.
  #
  get '/api/v2.0/pods/search/flat.hash.json' do
    cors_allow_all
    
    flat_result search, params do |pod|
      pod.to_hash
    end
  end
  
  # Returns a flat list of ids in the JSON format.
  #
  get '/api/v2.0/pods/search/flat.ids.json' do
    cors_allow_all
    
    flat_result search, params do |pod|
      pod.id
    end
  end
  
  require File.expand_path('../helpers', __FILE__)

end
