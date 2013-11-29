$:.unshift File.dirname(__FILE__)
require_relative '../header_test'
require_relative '../../lib/webdamlog_runner'

require 'test/unit'

# Test program with seeds ie. relation or peer name variables



# Test the method in program to rewrite unbound rules into seed rule
class TcWlSeedRewriteUnboundRule < Test::Unit::TestCase
  include MixinTcWlTest

  def setup
    @pg = <<-EOF
peer test_seed=localhost:11110;
peer p1=localhost:11111;
peer p2=localhost:11112;
peer p3=localhost:11113;
collection ext persistent local1@test_seed(atom1*,atom2*,atom3*);
collection ext per local2@test_seed(atom1*,atom2*);
collection ext per local3@test_seed(atom1*,atom2*);
collection ext per local4@test_seed(atom1*,atom2*);
collection ext persistent relname@test_seed(atom1*);
collection ext persistent peername@test_seed(atom1*);
fact local@test_seed(1);
fact local@test_seed(2);
fact local@test_seed(3);
fact local@test_seed(4);
fact relname@test_seed(local1);
fact relname@test_seed(local2);
fact peername@test_seed(p1);
fact peername@test_seed(p2);
fact peername@test_seed(p3);
fact peername@test_seed(p4);
end
    EOF
    @username = "test_seed"
    @port = "11110"
    @pg_file = "test_seed_install_local"
    File.open(@pg_file,"w"){ |file| file.write @pg }
  end

  def teardown
    File.delete(@pg_file) if File.exists?(@pg_file)
    ObjectSpace.each_object(WLRunner) do |obj|
      clean_rule_dir obj.rule_dir
      obj.delete
    end
    ObjectSpace.garbage_collect
  end

  def test_seed_rewrite_unbound_rules
    pg = WLBud::WLProgram.new(@username, @pg_file, 'localhost', @ip)

    test_string = 
      "rule local1@test_seed($h1,$h2,$h3) :- local2@test_seed($l1,$h1),local3@test_seed($l1,$s1),local4@test_seed($s2,$l3),$s1@test_seed($h2,$h3),local4@test_seed($_,$s2);"
    result = pg.parse test_string, true

    assert_equal(
      "rule local1_at_test_seed($h1, $h2, $h3) :- local2_at_test_seed($l1, $h1), local3_at_test_seed($l1, $s1), local4_at_test_seed($s2, $l3), $s1_at_test_seed($h2, $h3), local4_at_test_seed($_, $s2);",
      result.show_wdl_format)

    # the method we want to test
    pg.rewrite_rule result

    # test the split in two parts
    assert_equal ["local2_at_test_seed($l1, $h1)","local3_at_test_seed($l1, $s1)","local4_at_test_seed($s2, $l3)"],
      result.bound.map { |e| e.show_wdl_format }
    assert_equal ["$s1_at_test_seed($h2, $h3)", "local4_at_test_seed($_, $s2)"],
      result.unbound.map { |e| e.show_wdl_format }
    assert_equal "local1_at_test_seed($h1, $h2, $h3)", result.head.show_wdl_format

    new_dec = pg.flush_new_local_declaration
    
    # test the new seed relation to declare
    assert_equal "intermediary seed_rule_1_1_at_test_seed( seed_rule_1_1_h1_0*,seed_rule_1_1_s1_1*,seed_rule_1_1_s2_2* ) ;",
      new_dec.first.show_wdl_format

    arr_new_rul = pg.flush_new_seed_rule_to_install
    new_rul = arr_new_rul.first.first
    new_ato = arr_new_rul.first[1]
    new_ste = arr_new_rul.first[2]

    # test the new seed rule installed locally
    assert_equal "rule seed_rule_1_1_at_test_seed($h1, $s1, $s2) :- local2_at_test_seed($l1, $h1), local3_at_test_seed($l1, $s1), local4_at_test_seed($s2, $l3);",
      new_rul.show_wdl_format

    assert_equal "seed_rule_1_1@test_seed($h1,$s1,$s2)", new_ato

    assert_equal "rule local1_at_test_seed($h1, $h2, $h3):-seed_rule_1_1@test_seed($h1,$s1,$s2),$s1@test_seed($h2,$h3),local4@test_seed($_,$s2);", new_ste
  end
  
end
