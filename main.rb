require "rubygems"
require "sinatra"

class Main < Sinatra::Base
  get "/" do
    "You just deployed an app!!!!!!!!!!!"
  end
end
