#!/usr/bin/ruby

# TestFS for RFuse

require "rfuse"
require 'socket'
require 'pry'
require 'pry-debugger'
require  'logger'

class MyDir < Hash
  attr_accessor :name, :mode , :actime, :modtime, :uid, :gid
  def initialize(name,mode)
    @uid=0
    @gid=0
    @actime=Time.now
    @modtime=Time.now
    @xattr=Hash.new
    @name=name
    @mode=mode
  end

  def stat
    RFuse::Stat.directory(mode,:uid => uid, :gid => gid, :atime => actime, :mtime => modtime,
                          :size => size)
  end

  def listxattr()
    @xattr.keys()
  end
  def setxattr(name,value,flag)
    @xattr[name]=value #TODO:don't ignore flag
  end
  def getxattr(name)
    return @xattr[name]
  end
  def removexattr(name)
    @xattr.delete(name)
  end
  def size
    return 48 #for testing only
  end
  def isdir
    true
  end
  def insert_obj(obj,path)
    d=self.search(File.dirname(path))
    if d.isdir then
      d[obj.name]=obj
    else
      raise Errno::ENOTDIR.new(d.name)
    end
    return d
  end
  def remove_obj(path)
    d=self.search(File.dirname(path))
    d.delete(File.basename(path))
  end
  def search(path)
    p=path.split('/').delete_if {|x| x==''}
    if p.length==0 then
      return self
    else
      return self.follow(p)
    end
  end
  def follow (path_array)
    if path_array.length==0 then
      return self
    else
      d=self[path_array.shift]
      if d then
        return d.follow(path_array)
      else
        raise Errno::ENOENT.new
      end
    end
  end
  def to_s
    return "Dir: " + @name + "(" + @mode.to_s + ")"
  end
end

class MyFile
  attr_accessor :name, :mode, :actime, :modtime, :uid, :gid, :content
  def initialize(name,mode,uid,gid)
    @actime=0
    @modtime=0
    @xattr=Hash.new
    @content=""
    @uid=uid
    @gid=gid
    @name=name
    @mode=mode
  end

  def stat
    RFuse::Stat.file(mode,:uid => uid, :gid => gid, :atime => actime, :mtime => modtime,
                     :size => size)
  end

  def listxattr()
    @xattr.keys
  end

  def setxattr(name,value,flag)
    @xattr[name]=value #TODO:don't ignore flag
  end

  def getxattr(name)
    return @xattr[name]
  end
  def removexattr(name)
    @xattr.delete(name)
  end
  def size
    return content.size
  end 
  def isdir
    false
  end
  def follow(path_array)
    if path_array.length != 0 then
      raise Errno::ENOTDIR.new
    else
      return self
    end
  end
  def to_s
    return "File: " + @name + "(" + @mode.to_s + ")"
  end
end

class MyFuse 

  attr_reader :root

  def initialize(root, client)
    @client = client
    @root=root
  end

  # The new readdir way, c+p-ed from getdir
  def readdir(ctx,path,filler,offset,ffi)
    d=@root.search(path)
    if d.isdir then
      d.each {|name,obj| 
        filler.push(name,obj.stat,0)
      }
    else
      raise Errno::ENOTDIR.new(path)
    end
  end

  def getattr(ctx,path)
    d = @root.search(path)
    #d_s = @client.getattr ctx, path
    return d.stat
  end #getattr

  def mkdir_sync(path, mode)
    @root.insert_obj(MyDir.new(File.basename(path),mode),path)
  end

  def mkdir(ctx,path,mode)
    @root.insert_obj(MyDir.new(File.basename(path),mode),path)
    @client.mkdir ctx, path, mode
  end #mkdir

  def mknod_sync path, mode, uid, gid
    @root.insert_obj(MyFile.new(File.basename(path),mode,uid,gid),path)
  end

  def mknod(ctx,path,mode,major,minor)
    @root.insert_obj(MyFile.new(File.basename(path),mode,ctx.uid,ctx.gid),path)
  end #mknod

  def open(ctx,path,ffi)
  end

  #def release(ctx,path,fi)
  #end

  #def flush(ctx,path,fi)
  #end

  def chmod(ctx,path,mode)
    d=@root.search(path)
    d.mode=mode
  end

  def chown(ctx,path,uid,gid)
    d=@root.search(path)
    d.uid=uid
    d.gid=gid
  end

  def truncate(ctx,path,offset)
    d=@root.search(path)
    d.content = d.content[0..offset]
  end

  def utime(ctx,path,actime,modtime)
    d=@root.search(path)
    d.actime=actime
    d.modtime=modtime
  end

  def unlink(ctx,path)
    @root.remove_obj(path)
  end

  def rmdir(ctx,path)
    @root.remove_obj(path)
    @client.rmdir path
  end

  #def symlink(ctx,path,as)
  #end

  def rename(ctx,path,as)
    d = @root.search(path)
    @root.remove_obj(path)
    @root.insert_obj(d,path)
  end

  #def link(ctx,path,as)
  #end

  def read(ctx,path,size,offset,fi)
    d = @root.search(path)
    if (d.isdir) 
      raise Errno::EISDIR.new(path)
      return nil
    else
      return d.content[offset..offset + size - 1]
    end
  end

  def write_sync path, content
    d=@root.search(path)
    if (d.isdir) 
      raise Errno::EISDIR.new(path)
    else
      d.content = content
    end
  end

  def write(ctx,path,buf,offset,fi)
    d=@root.search(path)
    if (d.isdir) 
      raise Errno::EISDIR.new(path)
    else
      d.content[offset..offset+buf.length - 1] = buf
      @client.write path, d.content
      #@client.write ctx, path, buf, offset, fi
    end
    return buf.length
  end

  # removed name
  def setxattr(ctx,path,name,value,flags)
    d=@root.search(path)
    d.setxattr(name,value,flags)
  end

  def getxattr(ctx,path,name)
    d=@root.search(path)
    if (d) 
      value=d.getxattr(name)
      if (!value)
        value=""
        #raise Errno::ENOENT.new #TODO raise the correct error :
        #NOATTR which is not implemented in Linux/glibc
      end
    else
      raise Errno::ENOENT.new
    end
    return value
  end

  def listxattr(ctx,path)
    d=@root.search(path)
    value= d.listxattr()
    return value
  end

  def removexattr(ctx,path,name)
    d=@root.search(path)
    d.removexattr(name)
  end

  #def opendir(ctx,path,ffi)
  #end

  #def releasedir(ctx,path,ffi)
  #end

  #def fsyncdir(ctx,path,meta,ffi)
  #end

  # Some random numbers to show with df command
  def statfs(ctx,path)
    s = RFuse::StatVfs.new()
    s.f_bsize    = 1024
    s.f_frsize   = 1024
    s.f_blocks   = 1000000
    s.f_bfree    = 500000
    s.f_bavail   = 990000
    s.f_files    = 10000
    s.f_ffree    = 9900
    s.f_favail   = 9900
    s.f_fsid     = 23423
    s.f_flag     = 0
    s.f_namemax  = 10000
    return s
  end

  def ioctl(ctx, path, cmd, arg, ffi, flags, data)
    # FT: I was not been able to test it.
    print "*** IOCTL: command: ", cmd, "\n"
  end

  def poll(ctx, path, ffi, ph, reventsp)
    print "*** POLL: ", path, "\n"
    # This is how we notify the caller if something happens:
    ph.notifyPoll();
    # when the GC harvests the object it calls fuse_pollhandle_destroy
    # by itself.
  end

  def init(ctx,rfuseconninfo)
    print "RFuse TestFS started\n"
    print "init called\n"

    print "proto_major:#{rfuseconninfo.proto_major}\n"
  end

end #class Fuse

class MyClient

  def initialize path
    @path = path
    @client = TCPSocket.open 'localhost', 3000
    @log = Logger.new STDOUT
  end

  def set_fuse fuse
    @fuse = fuse
  end

  def close
    @client.close
  end

  def sync
    self.send_obj ["sync"]
    folders = YAML::load @client.recv 50000
    @log.debug "Received "+folders.inspect
    folders.each do |folder|
      @fuse.mkdir_sync folder[:path], folder[:mode]
    end
    #num_files = YAML::load @client.recv 5000
    #@log.debug "Receiving #{num_files} files"
    #num_files.to_i.times do
    #file = YAML::load @client.recv(500000)
    #@log.debug "Received "+file.inspect
    #@fuse.mknod_sync file[:path], file[:mode], file[:uid], file[:gid]
    #@fuse.write_sync file[:path], file[:content]
    #end
    files = YAML::load @client.recv 5000000
    @log.info "Received "+files.inspect
    files.each do |file|
      @fuse.mknod_sync file[:path], file[:mode], file[:uid], file[:gid]
      @fuse.write_sync file[:path], file[:content]
    end
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
    @client.write YAML::dump obj
  end

  def recv_obj
    YAML::load @client.recv(5000)
  end
end


if ARGV.length == 0
  print "\n"
  print "Usage: [ruby [--debug]] #{$0} mountpoint [mount_options...]\n"
  print "\n"
  print "   mountpoint must be an existing directory\n"
  print "   mount_option '-h' will list supported options\n"
  print "\n"
  print "   For verbose debugging output use --debug to ruby\n"
  print "   and '-odebug' as mount_option\n"
  print "\n"
  exit(1)
end

@client = MyClient.new ARGV[0]

fs = MyFuse.new(MyDir.new("",0777), @client)
@client.set_fuse fs

fo = RFuse::FuseDelegator.new(fs,*ARGV)

@client.sync

if fo.mounted?
  Signal.trap("TERM") { print "Caught TERM\n" ; fo.exit; @client.close; exit }
  Signal.trap("INT") { print "Caught INT\n"; fo.exit; @client.close; exit }
  begin
    fo.loop
  rescue
    print "Error:" + $!
  ensure
    fo.unmount if fo.mounted?
    print "Unmounted #{ARGV[0]}\n"
  end
end


