# Contains helpers for the API.
#
CocoapodSearch.helpers do
  
  @api_routes = []
  
  # Store a path for use in a global OPTIONS endpoint.
  #
  def self.store path
    @api_routes << path
  end
  
  # Return all API routes in their original form.
  #
  def self.api_routes
    @api_routes
  end
  
  @versioned_accepts = {}
  
  # Creates two API endpoints:
  #   1. Comfortable URL-based.
  #   2. HTTP header-based.
  #
  def self.api version, structure, item_structure, format, accepts, &search
    # If there is a version, we install a comfy browser-accessible path.
    #
    if version
      convenient_path = "/api/v#{version}/pods.#{structure}.#{item_structure}.#{format}"
    
      store convenient_path
    
      # Create a convenient browser-accessible endpoint.
      #
      get convenient_path do
        cors_allow_all
      
        instance_eval &search
      end
      
      options convenient_path do
        response['Allow'] = 'GET,OPTIONS'
        json GET: {
          description: "Perform a query and receive a #{structure} JSON result with result items formatted as #{item_structure}.",
          parameters: {
            query: {
              type: "string",
              description: "The search query. All Picky special characters are allowed and used.",
              required: true                
            },
            ids: {
              type: "integer",
              description: "How many result ids and items should be returned with the result.",
              required: false,
              default: 20
            },
            offset: {
              type: "integer",
              description: "At what position the query results should start.",
              required: false,
              default: 0
            }
          },
          example: {
            query: "af networking",
            ids: 50,
            offset: 0
          }
        }
      end
    end
    
    # Store the accepts.
    #
    @versioned_accepts[version && version.to_s] ||= {}
    accepts[:accept].each do |accept|
      @versioned_accepts[version && version.to_s][accept] = search
    end
  end
  def self.install_machine_api
    versioned_accepts = @versioned_accepts
    
    machine_path = '/api/pods'
    
    # Create a machine/command-line accessible endpoint.
    #
    get machine_path do
      cors_allow_all
      
      request.accept.each do |accept|
        version = versioned_accepts[accept.params['version']] || next
        handler = version[accept.to_s] || next
        halt (handler && instance_eval(&handler) || next)
      end
      
      halt 406
    end
  end
  
  # Returns a Picky style search result (including how results were found etc.)
  #
  # More info here: https://github.com/floere/picky/wiki/Results-format-and-structure.
  #
  def picky_result search, params, &rendering
    results = search.interface.search params[:query], params[:ids] || 20, params[:offset] || 0
    results = results.to_hash
    results.extend Picky::Convenience
    
    results.populate_with Pod::View, &rendering
    
    results
  end
  
  # Returns a list style search result – just a list of results (in your rendered format).
  #
  def flat_result search, params, &rendering
    results = search.interface.search params[:query], params[:ids] || 20, params[:offset] || 0
    
    flat_results = results.ids.map do |id|
      rendering.call Pod::View.content[id]
    end
    
    flat_results
  end
  
  # Allow all origins.
  #
  def cors_allow_all
    response["Access-Control-Allow-Origin"] = "*"
  end
  
  # Encode as json.
  #
  def json results
    Yajl::Encoder.encode results
  end

end