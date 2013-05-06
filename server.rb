#!/usr/bin/ruby

require 'rubygems'
require 'bundler/setup'
require 'fileutils'
require 'socket'
require 'logger'
require 'pry'
require 'pry-debugger'
require 'rfuse'
require 'pathname'

class MyFile
  attr_accessor :uid, :gid, :pid, :path, :file
  def initialize uid, gid, pid, path, mode
    @uid = uid
    @pid = pid
    @gid = gid
    @path = path
    @file = File.new path, "w"
    @file.close
  end
end

class MyServer

  def initialize path
    @log = Logger.new(STDOUT)
    @server = TCPServer.new 3000
    @path = path
    @files = Array.new
  end

  def get_folders
    folders = Array.new
    Pathname.new(@path).children.select do |c|
      folders.push({ path: c.to_s.sub('server', ''), mode: c.stat.mode }) if c.directory?
    end
    folders
  end

  def get_files
    files = Array.new
    Pathname.new(@path).children.select do |c| 
      if c.file?
        files.push({
          path: c.to_s.sub('server', ''), 
          mode: c.stat.mode,
          uid: 0, 
          gid: 0
        })
      end
    end #.collect{ |p| p.to_s }
    files
  end

  def run
    begin
      loop do
        Thread.start(@server.accept) do |client|
          @log.info "Connection accepted"

          begin
            while (arguments = YAML::load client.recv(5000))
              @log.info "Received: "+arguments.inspect
              case arguments[0]
              when 'sync'
                client.write YAML::dump self.get_folders
                client.write YAML::dump self.get_files
              when 'mkdir'
                self.mkdir arguments[1], arguments[2]
              when 'mknod'
                self.mknod arguments[1], arguments[2], arguments[3]
              end
            end
          rescue Exception => e
            Thread.main.raise e
          end
          @log.info "Connection closed"

        end
      end
    rescue Exception => e
      Thread.main.raise e
    end
  end

  def mknod ctx, path, mode
    begin
      @log.info "Mknod "+@path+path
      @files.push MyFile.new ctx.uid, ctx.gid, ctx.pid, @path+path, mode
    rescue Exception => e
      Thread.main.raise e
    end

  end

  def mkdir path, mode
    begin
      @log.info "Mkdir "+@path+path
      FileUtils.mkdir_p @path+path
    rescue Exception => e
      print e
    end
  end

end

MyServer.new(ARGV[0]).run

