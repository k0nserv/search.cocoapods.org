require File.expand_path '../lib/cocoapods.org', __FILE__

# Store the indexes in tmp.
#
Picky.root = 'tmp'

# The Sinatra search server.
#
# Mainly offers two things:
#  * Search API methods.
#  * Index update URL for the Github update hook.
#
class CocoapodSearch < Sinatra::Application

  def self.analytics
    if defined?(Gabba)
      @analytics_counter ||= 0
      @analytics = Gabba::Gabba.new('UA-29866548-5', 'cocoapods.org') if @analytics_counter % 100 == 0
      @analytics_counter += 1
    end
    @analytics
  end

  # Data container and search.
  #
  pods = Pods.new Pathname.new ENV['COCOAPODS_SPECS_PATH'] || './tmp/specs'
  search = Search.new pods

  self.class.send :define_method, :prepare do |force = false|
    search.reindex force
  end

  self.class.send :define_method, :dump_indexes do
    search.dump
  end

  self.class.send :define_method, :load_indexes do
    search.load
  end

  set :logging, false

  # search.cocoapods.org API 2.0
  #
  # Follows this convention:
  #
  # /api/<version>/<result collection>.<result structure>.<result item format>.<result format>?<query params>
  #
  # Explanation:
  # * /api This is the API of search.cocoapods.org.
  # * <version> Version 2.0 of the API.
  # * <result collection> What you are searching. Available:
  #   * pods Result items will be pods.
  # * <result structure> How the results are structured. Available:
  #   * flat Results are a flat list of result items without extra information.
  #   * picky https://github.com/floere/picky/wiki/Results-format-and-structure
  # * <result item format> The format of each item in the results. Available:
  #   * hash A hash representing the result item.
  #   * ids Just the id of a result item.
  # * <result format> The data format of the results. Available:
  #   * json
  # * <query params> Options to filter. Available:
  #   * query A Picky style query.
  #   * ids The amount of ids wanted.
  #   * offset The offset in the results.
  #
  # Example:
  #   http://search.cocoapods.org/api/v1/pods.picky.hash.json?query=author:eloy&ids=20&offset=0
  #

  # Machine based API:
  #
  # Example:
  #   curl http://search.cocoapods.org/api/pods?query=test -H "Accept: application/vnd.cocoapods.org+picky.hash.json; version=1"
  #   curl http://search.cocoapods.org/api/pods?query=test -H "Accept: application/vnd.cocoapods.org+picky.ids.json; version=1"
  #   curl http://search.cocoapods.org/api/pods?query=test -H "Accept: application/vnd.cocoapods.org+flat.hash.json; version=1"
  #   curl http://search.cocoapods.org/api/pods?query=test -H "Accept: application/vnd.cocoapods.org+flat.ids.json; version=1"
  #

  # Helpers used by the API.
  #
  require File.expand_path('../api_helpers', __FILE__)

  # Default endpoint returns the latest picky hash version.
  #
  api nil, :flat, :ids, :json, accept: ['*/*', 'text/json', 'application/json'] do
    CocoapodSearch.track_view request, :'default-flat/ids/json'
    json picky_result(search, pods.view, params) { |item| item[:id] }
  end

  # Returns a Picky style result with entries rendered as a hash.
  #
  api 1, :picky, :hash, :json, accept: ['application/vnd.cocoapods.org+picky.hash.json'] do
    CocoapodSearch.track_view request, :'picky/hash/json'
    json picky_result(search, pods.view, params) { |item| item }
  end

  # Returns a Picky style result with just ids as entries.
  #
  api 1, :picky, :ids, :json, accept: ['application/vnd.cocoapods.org+picky.ids.json'] do
    CocoapodSearch.track_view request, :'picky/ids/json'
    json picky_result(search, pods.view, params) { |item| item[:id] }
  end

  # Returns a flat list of results with entries rendered as a hash.
  #
  api 1, :flat, :hash, :json, accept: ['application/vnd.cocoapods.org+flat.hash.json'] do
    CocoapodSearch.track_view request, :'flat/hash/json'
    json flat_result(search, pods.view, params) { |item| item }
  end

  # Returns a flat list of ids.
  #
  api 1, :flat, :ids, :json, accept: ['application/vnd.cocoapods.org+flat.ids.json'] do
    CocoapodSearch.track_view request, :'flat/ids/json'
    json flat_result(search, pods.view, params) { |item| item[:id] }
  end

  # Installs API for calls using Accept.
  #
  install_machine_api

  # Temporary for CocoaDocs till we separate out API & html
  #
  # TODO Remove (ask orta).
  #
  get '/api/v1.5/pods/search' do
    cors_allow_all

    results = search.interface.search params[:query], params[:amount] || params[:ids] || 20, params[:'start-at'] || params[:offset] || 0
    results = results.to_hash
    results.extend Picky::Convenience

    results.amend_ids_with results.ids.map { |id| pods.view[id] }

    json results.entries
  end

  # Pod API code.
  #
  # TODO Remove -> Trunk will handle this.
  #
  # Currently only used by @fjcaetano for badge handling.
  #
  get '/api/v1/pod/:name.json' do
    pod = pods.specs[params[:name]]
    pod && json(pod.to_hash) || status(404) && body("Pod not found.")

    # TODO Replace at least with:
    #
    # pod = pods.view[params[:name]]
    # pod && json(pod) || status(404) && body("Pod not found.")
  end

  # Returns a JSON hash with helpful content with "no results" specific to cocoapods.org.
  #
  # TODO Move this into an API?
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

  # Experimental APIs.
  #
  get '/api/v1/pods.facets.json' do
    normalized_params = params.inject({}) do |result, (param, value)|
      result[param.gsub(/\-/, '_').to_sym] = Integer(value) rescue value
      result
    end
    CocoapodSearch.track_facets request
    body json search.facets normalized_params
  end

  # Code to reindex in the master.
  #
  reindexer = Master.new try_in_child: false do |child|
    search.reindex true

    if ENV['TRACE_RUBY_OBJECT_ALLOCATION']
      # Profiling.
      #
      # Analyze using:
      # cat heap.json |
      # ruby -rjson -ne ' obj = JSON.parse($_).values_at("file","line","type"); puts obj.join(":") if obj.first ' |
      # sort      |
      # uniq -c   |
      # sort -n   |
      # tail -20
      #
      GC.start full_mark: true, immediate_sweep: true
      ObjectSpace.dump_all output: File.open('heap.json', 'w')
    end

    # Hand over work to successor Unicorn master.
    #
    # Note: Not doing that currently as on Heroku, the restart in this manner does not work.
    #
    # Process.kill 'TERM', Process.pid
  end

  # Get and post hooks for triggering index updates.
  #
  [:get, :post].each do |type|
    send type, "/post-receive-hook/#{ENV['HOOK_PATH']}" do
      begin
        reindexer.run 'reindex'

        status 200
        body "REINDEXING"
      rescue StandardError => e
        status 500
        body e.message
      end
    end
  end

  # Tracking convenience methods.
  #
  def self.track_search query, total
    analytics && analytics.event(:pods, :search, query, total)
  end
  def self.track_facets request
    analytics && analytics.event(:pods, :facets, request.query_string)
  end
  def self.track_view request, title
    analytics && analytics.page_view(title, request.path)
  end

end
