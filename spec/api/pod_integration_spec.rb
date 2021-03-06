# coding: utf-8
#
require File.expand_path '../../spec_helper', __FILE__
require 'rack/test'

describe 'Search Integration Tests' do
  
  extend Rack::Test::Methods
  
  def app
    CocoapodSearch
  end
  
  ok do
    get "/api/v1/pod/_.m.json"
    last_response.status.should == 200
    last_response.body.should == "{\"name\":\"_.m\",\"version\":\"0.1.2\",\"summary\":\"_.m is a port of Underscore.jsto Objective-C.\",\"description\":\"                    _.m is a port of [Underscore.js](http://underscorejs.org/) to Objective-C. It strives to provide the fullest feature set possible in a way that is familiar to JavaScript developers (despite the differences between JavaScript and Objective-C).\\n\\n                    To help achieve this vision, _.m uses [SubjectiveScript.m](https://github.com/kmalakoff/SubjectiveScript.m) to bring JavaScript-like syntax and features into Objective-C, and [QUnit.m](https://github.com/kmalakoff/QUnit.m) to port unit tests from JavaScript to Objective-C. You should check them out, too!\\n\\n                    Full documentation can be found on the [_.m Website](http://kmalakoff.github.com/_.m/)\\n\",\"homepage\":\"http://kmalakoff.github.com/_.m/\",\"license\":\"MIT\",\"authors\":{\"Kevin Malakoff\":\"kmalakoff@gmail.com\"},\"source\":{\"git\":\"https://github.com/kmalakoff/_.m.git\",\"tag\":\"0.1.2\"},\"platforms\":{\"ios\":\"5.0\",\"osx\":\"10.7\"},\"requires_arc\":true,\"source_files\":\"Classes\",\"public_header_files\":\"Classes/**/*.h\",\"dependencies\":{\"SubjectiveScript.m\":[\"~> 0.1.2\"]}}"
  end

end
