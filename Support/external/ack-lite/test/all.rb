require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
_Root = File.expand_path(File.dirname(__FILE__)+'/..')
require File.join(_Root,'/ack-lite')

describe Hipe::AckLite do
  it "should build request" do
    request = Hipe::AckLite::Request.new([], [], '.','foo', '')
    validated = Hipe::AckLite::Service.validate(request)
    re = /foo/
    re.must_equal validated.regexp
  end

  it "should fail on bad request with opts" do
    request = Hipe::AckLite::Request.new([], [], '.','foo', 'abc')
    e = proc do
      validated = Hipe::AckLite::Service.validate(request)
    end.must_raise Hipe::AckLite::Failey
    e.message.must_match %r{'a'\. Expecting 'i','m', or 'x'}
  end

  it "should return list of files" do
    path = './test/data'
    # path = File.join(_Root, 'test')
    # FileUtils.cd(path)
    request = Hipe::AckLite::Request.new(['*.def'],[],path)
    files = Hipe::AckLite::Service.files(request)
    tgt = Set.new([
      "./test/data/do-me/xyz.def", "./test/data/uvw.def", "./test/data/abc.def"
    ])
    have = files.to_set
    (have.subset? tgt).must_equal true
    (tgt.subset? have).must_equal true
  end


end
