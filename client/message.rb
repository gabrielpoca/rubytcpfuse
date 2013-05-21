require 'active_record'

class Message < ActiveRecord::Base
  attr_accessible :id, :message
end
