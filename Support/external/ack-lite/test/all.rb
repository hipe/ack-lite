require 'minitest/autorun'  # unit and spec
require 'ruby-debug'

class HipeAckliteSpec < MiniTest::Spec
  GemRoot = File.expand_path(File.dirname(__FILE__)+'/..')
  def self.skipit msg, &b
    puts "skipping: #{msg}"
  end
end

require HipeAckliteSpec::GemRoot + '/ack-lite'
require HipeAckliteSpec::GemRoot + '/auxilliary/test/all'

describe Hipe::AckLite do

  def setup_chdir
    FileUtils.chdir(self.class::GemRoot)
  end

  def thing
    @thing ||= begin
      Hipe::AckLite::Request.build(
        :file_include_patterns => ['.rb'],
        :directory_ignore_patterns => ['.git'],
        :search_paths => ['.'],
        :regexp_string => 'foo',
        :grep_opts_argv => ['-i']
      )
    end
  end

  it "should make request with hash" do
    thing.wont_be_nil
  end

  it "should fail with bad first level args" do
    proc do
      Hipe::AckLite::Request.build(:blah=>'blah')
    end.must_raise(NoMethodError)
  end

  it "should make request with flat args" do
    request = Hipe::AckLite::Request.build(['.git'], ['.rb'],
      ['.'], 'foo', ['-i']
    )
    request.wont_be_nil
    request.must_equal thing
  end

  it "should produce a valid shell command when you build the request" do
    request = Hipe::AckLite::Service.build_request(
      ['.git'], ['.rb'], ['.'], 'foo', ['-i']
    )
    # careful - fragile as all gitup.  leave no trailing spaces
    shell_cmd = <<-'SHELL_CMD'.gsub(/\n      /m,'').strip
      find -L .  -not \( -type d \( -name .git \) -prune  \) -a \( -name ".rb"
       \) -exec grep --extended-regexp --binary-files=without-match
      --line-number --with-filename -i  foo  {} ';'
    SHELL_CMD
    request.shell_command.must_equal shell_cmd
  end

  it "should return list of files" do
    setup_chdir
    request = Hipe::AckLite::Request.build(
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
    setup_chdir
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
    f1 = ((have.subset? tgt).must_equal true)
    f2 = ((tgt.subset? have).must_equal true)
  end

  it "should do case sensitive" do
    setup_chdir
    results = Hipe::AckLite::Service.search(
      ['skip-me'],[],['./test/data'],'abc',[]
    )
    results.list.size.must_equal 1
  end

  it "should do case insensitive" do
    setup_chdir
    results = Hipe::AckLite::Service.search(
      ['skip-me'],[],['./test/data'],'abc',['-i']
    )
    results.list.size.must_equal 2
  end

  it "should throw on bad options passed to grep" do
    setup_chdir
    e  = proc do
      Hipe::AckLite::Service.search(
        ['skip-me'],[],['./test/data'],'abc',['-j']
      )
    end.must_raise(Hipe::AckLite::Fail)
    e.message.must_match(/grep: invalid option -- j/)
  end

end
