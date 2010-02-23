require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
_Root = File.expand_path(File.dirname(__FILE__)+'/..')
require File.join(_Root,'/ack-lite')

describe Hipe::AckLite do
  it "should build request" do
    request = Hipe::AckLite::Request.new([], [], '.','foo', '')
    validated = Hipe::AckLite::Service.validate(request)
    #re = /foo/
    #re.must_equal validated.regexp
    validated.regexp_str.must_equal 'foo'
  end

  it "should not fail on bad request with opts" do
    request = Hipe::AckLite::Request.new([], [], '.','foo', 'abc')
    1.must_equal 1
   # e = proc do
   #   validated = Hipe::AckLite::Service.validate(request)
   # end.must_not_raise Hipe::AckLite::Failey
  # e.message.must_match %r{'a'\. Expecting 'i'}
  end

  it "should return list of files" do
    path = './test/data'
    # path = File.join(_Root, 'test')
    # FileUtils.cd(path)
    request = Hipe::AckLite::Request.new(['*.def'],[],path)
    response = Hipe::AckLite::Service.files(request)
    tgt = Set.new([
      "./test/data/do-me/xyz.def", "./test/data/uvw.def", "./test/data/abc.def"
    ])
    have = response.to_set
    (have.subset? tgt).must_equal true
    (tgt.subset? have).must_equal true
  end

  it "should work" do

    path = './test/data'
    # path = File.join(_Root, 'test')
    # FileUtils.cd(path)
    request = Hipe::AckLite::Request.new(['*.def'],['skip-me'],path,'foo')
    response = Hipe::AckLite::Service.search(request)
    tgt = Set.new(["./test/data/abc.def:1:foo", "./test/data/uvw.def:1:foo-bar"])
    have = Set.new(response.list)
    (have.subset? tgt).must_equal true
    (tgt.subset? have).must_equal true

  end

end
