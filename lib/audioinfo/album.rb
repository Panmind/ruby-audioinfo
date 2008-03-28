require "audioinfo"

class AudioInfo::Album

  IMAGE_EXTENSIONS = %w{jpg jpeg gif png}

  # a regexp to match the "multicd" suffix of a "multicd" string
  # example: "toto (disc 1)" will match ' (disc 1)'
  MULTICD_REGEXP = /\s*(\(|\[)?\s*(disc|cd):?-?\s*(\d+).*(\)|\])?\s*$/i

  attr_reader :files, :files_on_error, :discnum, :multicd, :basename, :infos, :path

  # return the list of images in the album directory, with "folder.*" in first
  def self.images(path)
    arr = Dir.glob( File.join(path, "*.{#{IMAGE_EXTENSIONS.join(",")}}"), File::FNM_CASEFOLD).collect do |f| 
      File.expand_path(f)
    end
    # move "folder.*" image on top of the array
    if folder = arr.detect { |f| f =~ /folder\.[^.]+$/ }
      arr.delete(folder)
      arr.unshift(folder)
    end
    arr
  end

  # strip the "multicd" string from the given +name+
  def self.basename(name)
    name.sub(MULTICD_REGEXP, '')
  end

  # return the number of the disc in the box or 0
  def self.discnum(name)
    if name =~ MULTICD_REGEXP
      $3.to_i
    else
      0
    end
  end

  # open the Album with +path+. +fast_lookup+ will only check 
  # first and last file of the directory
  def initialize(path, fast_lookup = false)
    @path = path
    @multicd = false
    @basename = @path
    exts = AudioInfo::SUPPORTED_EXTENSIONS.join(",")

    # need to escape the glob path
    glob_escaped_path = @path.gsub(/([{}?*\[\]])/) { |s| '\\' << s }

    file_names = Dir.glob( File.join(glob_escaped_path, "*.{#{exts}}") , File::FNM_CASEFOLD).sort

    if fast_lookup
      file_names = [file_names.first, file_names.last]
    end

    @files_on_error = []

    @files = file_names.collect do |f|
      begin
        AudioInfo.new(f) 
      rescue AudioInfoError
        @files_on_error << f
	nil
      end
    end.compact

    if @files_on_error.empty?
      @files_on_error = nil
    end
    
    @infos = {}
    @infos["album"] = @files.collect { |i| i.album }.uniq
    @infos["album"] = @infos["album"].first if @infos["album"].size == 1
    artists = @files.collect { |i| i.artist }.uniq
    @infos["artist"] = artists.size > 1 ? "various" : artists.first
    @discnum = self.class.discnum(@infos["album"])

    if not @discnum.zero?
      @multicd = true
      @basename = self.class.basename(@infos["album"])
    end
  end

  # is the album empty?
  def empty?
    @files.empty?
  end

  # are all the files of the album MusicBrainz tagged ?
  def mb_tagged?
    return false if @files.empty?
    mb = true
    @files.each do |f|
      mb &&= f.mb_tagged?
    end
    mb
  end
  
  # return an array of images with "folder.*" in first
  def images
    self.class.images(@path)
  end

  # title of the album
  def title
    albums = @files.collect { |f| f.album }.uniq
    #if albums.size > 1
    #  "#{albums.first} others candidates: '" + albums[1..-1].join("', '") + "'"
    #else
      albums.first
    #end
  end

  # mbid (MusicBrainz ID) of the album
  def mbid
    return nil unless mb_tagged?
    @files.collect { |f| f.musicbrainz_infos["albumid"] }.uniq.first
  end

  # is the album multi-artist?
  def va?
    @files.collect { |f| f.artist }.uniq.size > 1
  end

  # pretty print
  def to_s
    out = StringIO.new
    out.puts(@path)
    out.print "'#{title}'"
    
    unless va?
      out.print " by '#{@files.first.artist}' "
    end

    out.puts
    
    @files.sort_by { |f| f.tracknum }.each do |f|
      out.printf("%02d %s %3d %s", f.tracknum, f.extension, f.bitrate, f.title)
      if va?
	out.print(" "+f.artist)
      end
      out.puts
    end

    out.string
  end

end


