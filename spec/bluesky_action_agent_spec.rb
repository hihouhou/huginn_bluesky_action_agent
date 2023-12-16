require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::BlueskyActionAgent do
  before(:each) do
    @valid_options = Agents::BlueskyActionAgent.new.default_options
    @checker = Agents::BlueskyActionAgent.new(:name => "BlueskyActionAgent", :options => @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  pending "add specs here"
end
