#!/usr/bin/ruby

url = "http://dark.fhtr.org/repos"
libname = 'thumbnailer'

$LOAD_PATH.unshift "lib"
require "./lib/#{libname}.rb"
require 'fileutils'

version = Thumbnailer::VERSION

dn = "#{libname}-#{version}"
FileUtils.mkdir(dn)
%w(lib bin README INSTALL LICENSE setup.rb).each{|fn|
  FileUtils.cp_r(fn, dn)
}
`tar zcf #{dn}.tar.gz #{dn}`
FileUtils.rm_r(dn)
s = <<-EOF
tarball: #{url}/#{libname}/#{dn}.tar.gz
git: #{url}/#{libname}


#{File.read('README')}
EOF
File.open("release_msg-#{version}.txt", "w"){|f| f.write s}
