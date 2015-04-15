require 'unread/base'
require 'unread/dynamic_model'
require 'unread/readable'
require 'unread/reader'
require 'unread/scopes'
require 'unread/version'

ActiveRecord::Base.send(:include, Unread)
