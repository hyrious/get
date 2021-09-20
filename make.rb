# get information from
# [scoop](https://github.com/ScoopInstaller/Main),
# [winget](https://github.com/microsoft/winget-pkgs).
# build an index to dist/db.json

DB = []
# [{  id: '7zip',
#     kw: ['7z', '7zFM', '7-Zip'],
#    url: 'https://www.7-zip.org/download.html'
#    src: 'scoop' }]

# id = when :scoop  then basename
#      when :winget then guess from PackageIdentifier

# url = when :scoop  then checkver.url or checkver.github or homepage
#       when :winget then PackageUrl

# 1. fetch latest json/yaml data from github, like Rich-Harris/degit
# 2. unzip them, write to DB
# 3. save it to dist

require 'open-uri'
require 'stringio'
require 'json'
require 'zlib'
require 'rubygems'
require 'rubygems/package'

def fetch url
  puts "fetching #{url}"
  URI.open url, open_timeout: 3, &:read
rescue # try mirror links
  retry if url.sub! 'https://github.com', 'https://hub.fastgit.org'
end

def fetch_head repo_url
  `git ls-remote #{repo_url}`.lines(chomp: true).each do |row|
    hash, ref = row.split ?\t
    return hash if ref == 'HEAD'
  end
  raise "failed to fetch the HEAD of #{repo_url}"
end

def fetch_tgz repo_url, hash = nil
  hash ||= fetch_head repo_url
  gzip = fetch "#{repo_url}/archive/#{hash}.tar.gz"
  Zlib::GzipReader.new(StringIO.new(gzip)).read
end

def untar bin, &block
  Gem::Package::TarReader.new StringIO.new bin do |tar|
    return tar.each &block
  end
end

# to test it locally without hitting rate limit, turn on cache
unless ENV['CI']
  require 'tmpdir'
  TMPFILE = File.join Dir.tmpdir, 'hyrious-get-cache'
  Cache = File.exist?(TMPFILE) ? Marshal.load(IO.binread(TMPFILE)) : {}
  def flush
    IO.binwrite TMPFILE, Marshal.dump(Cache)
  end
  %i( fetch fetch_head ).each do |name|
    old = :"_#{name}_nocache"
    cache = Cache[name] ||= {}
    singleton_class.alias_method old, name
    define_method name do |*args|
      return (cache[args] ||= send(old, *args)).tap { flush }
    end
  end
end

SEEN = {}

def scoop repo_url
  untar fetch_tgz repo_url do |file|
    name = file.full_name
    if (i = name.index '/bucket/') and (j = name.rindex '.json')
      id = file.full_name[(i + '/bucket/'.size)...j]
      raw = JSON.parse file.read

      url = nil
      case raw['checkver']
      when String
        url = raw['homepage']
      when Hash
        url = raw['checkver']['url'] || raw['github'] || raw['homepage']
        if %w( .json .yaml .yml .txt ).any? { |e| url.end_with? e }
          url = raw['homepage']
        end
      end
      url = raw['homepage'] if url.nil?

      kw = [id]
      case raw['bin']
      when String
        kw << File.basename(raw['bin'].gsub('\\', '/'), '.*')
      when Array
        kw.push(*raw['bin'].flatten.map { |e| File.basename(e.gsub('\\', '/'), '.*') })
      end

      unless SEEN.key? id
        SEEN[id] = true
        DB.push({ id: id, kw: kw, url: url.force_encoding('utf-8'), src: 'scoop' })
      end
    end
  end
end

def winget repo_url
  untar fetch_tgz repo_url do |file|
    name = file.full_name
    if name.include? '/manifests/' and name.end_with? '.yaml'
      raw = file.read
      raw_id = raw.match(/PackageIdentifier:\s*(.+)/)&.[](1)&.chomp
      url = raw.match(/PackageUrl:\s*(.*)/)&.[](1)&.chomp
      if raw_id and url
        id = raw_id.split(?.).pop
        kw = raw_id
        unless SEEN.key? id
          SEEN[id] = true
          DB.push({ id: id, kw: [kw], url: url.force_encoding('utf-8'), src: 'winget' })
        end
      end
    end
  end
end

scoop 'https://github.com/ScoopInstaller/Main'
scoop 'https://github.com/lukesampson/scoop-extras'
winget 'https://github.com/microsoft/winget-pkgs'

Dir.mkdir 'public' unless Dir.exist? 'public'
data = JSON.generate(DB)
File.write 'public/db.json', data

puts "generated public/db.json #{data.bytesize} bytes"
