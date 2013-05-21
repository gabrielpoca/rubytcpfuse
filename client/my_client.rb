require 'thread'

require_relative 'message'

class MyClient

  attr_accessor :client

  def initialize path
    @path = path
    @log = Logger.new STDOUT
    @queue = ConditionVariable.new
  end

  def set_fuse fuse
    @fuse = fuse
  end

  def mkdir ctx, path, mode
    @log.info 'mkdir'
    self.send_obj ["mkdir", path, mode]
  end

  def write path, content
    puts "Write called"
    self.send_obj ["write", path, content]
  end

  def rmdir path
    self.send_obj ["rmdir", path]
  end

  def send_obj obj
    #@client.write YAML::dump obj
    Message.create message: (YAML::dump obj)
  end

  def recv_obj
    YAML::load @client.recv(5000)
  end

  # sync

  def wait
    @queue.wait
  end

  def notify
    @queue.signal
  end

  # connection

  def connect
    begin
      @client = TCPSocket.open 'localhost', 3000
    rescue
      return false
    end
  end 

  def close
    @client.close unless @client.nil?
  end

  def sync
    self.send_obj ["sync"]
    folders = YAML::load @client.recv 50000

    @log.debug "Received "+folders.inspect
    folders.each do |folder|
      @fuse.mkdir_sync folder[:path], folder[:mode]
    end

    files = YAML::load @client.recv 500000
    @log.info "Received "+files.inspect
    files.each do |file|
      @fuse.mknod_sync file[:path], file[:mode], file[:uid], file[:gid]
      @fuse.write_sync file[:path], file[:content]
    end
  end

end


