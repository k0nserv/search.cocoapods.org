require 'sinatra/base'
require 'i18n'
require 'picky'
require 'picky-client'
require 'haml'
require 'json'
require 'cocoapods-core'

# Loads the helper class for extracting the searched platform.
#
require File.expand_path '../lib/platform', __FILE__

# Extend Pod::Specification with the capability of ignoring bad specs.
#
require File.expand_path '../lib/pod/specification', __FILE__

# Extend Pod::Specification::Set with a few needed methods for indexing.
#
require File.expand_path '../lib/pod/specification/set', __FILE__

# Load a view proxy for dealing with "rendering".
#
require File.expand_path '../lib/pod/view', __FILE__

# Load pods data container.
#
require File.expand_path '../lib/pods', __FILE__

# Load search interface and index.
#
require File.expand_path '../lib/search', __FILE__

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
    search.index.reindex
  end
  
  set :logging,       false
  set :static,        true
  set :public_folder, File.dirname(__FILE__)
  set :views,         File.expand_path('../views', __FILE__)

  # Install get and post hooks for pod indexing.
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

  # Temporary for CocoaDocs till we separate out API & html 
  
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
  
  #
  #
  get '/api/v2.0/pods/search/picky/full' do
    cors_allow_all
    
    picky_result search, params do |pod|
      pod.render
    end
  end
  
  #
  #
  get '/api/v2.0/pods/search/short' do
    cors_allow_all
    
    flat_result search, params do |pod|
      pod.render_short_json
    end
  end
  
  #
  #
  get '/api/v2.0/pods/search/ids' do
    cors_allow_all
    
    flat_result search, params do |pod|
      pod.id
    end
  end
  
  require File.expand_path('../helpers', __FILE__)

end
