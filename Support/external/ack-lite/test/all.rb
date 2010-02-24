require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
_Root = File.expand_path(File.dirname(__FILE__)+'/..')
require File.join(_Root,'/ack-lite')

class HipeAckliteSpec < MiniTest::Spec
  def self.skipit msg, &b
    puts "skipping: #{msg}"
  end
end

describe Hipe::AckLite do

  def thing
    @thing ||= begin
      Hipe::AckLite::Request.make(
        :file_include_patterns => ['.rb'],
        :directory_ignore_patterns => ['.git'],
        :search_paths => ['.'],
        :regexp_string => 'foo',
        :regexp_opts_argv => ['-i']
      )
    end
  end

  it "should make request with hash" do
    thing.wont_be_nil
  end

  it "should fail with bad first level args" do
    proc do
      Hipe::AckLite::Request.make(:blah=>'blah')
    end.must_raise(NoMethodError)
  end

  it "should make request with flat args" do
    request = Hipe::AckLite::Request.make(['.git'], ['.rb'],
      ['.'], 'foo', ['-i']
    )
    request.wont_be_nil
    request.must_equal thing
  end

  it "should return list of files" do
    request = Hipe::AckLite::Request.new(
      [],
      ['*.def'],
      ['./test/data']
    )
    response = Hipe::AckLite::Service.files(request)
    tgt = Set.new([
      "./test/data/do-me/xyz.def",
      "./test/data/uvw.def",
      "./test/data/abc.def"
    ])
    have = response.to_set
    (have.subset? tgt).must_equal true
    (tgt.subset? have).must_equal true
  end

  it "should work" do
    response = Hipe::AckLite::Service.search(
      ['skip-me'],
      ['*.def'],
      ['./test/data'],
      'foo',
      []
    )
    tgt = Set.new([
      "./test/data/abc.def:1:foo",
      "./test/data/uvw.def:1:foo-bar"
    ])
    have = Set.new(response.list)
    (have.subset? tgt).must_equal true
    (tgt.subset? have).must_equal true

  end

end
