# ####License####
#  File name tc_simple_delegation.rb
#  Copyright © by INRIA
# 
#  Contributors : Webdam Team <webdam.inria.fr>
#       Emilien Antoine <emilien[dot]antoine[@]inria[dot]fr>
# 
#   WebdamLog - Jul 6, 2012
# 
#   Encoding - UTF-8
# ####License####
$:.unshift File.dirname(__FILE__)
# Note: important to load global variable before include since it could
# influence the behavior of inclusion
# $WL_TEST = true # changed for an options in hash of WL object
require 'header_test'

class TcWlDelegation1Simple < Test::Unit::TestCase
  include MixinTcWlTest

  @@first_test=true
  NUMBER_OF_TEST_PG = 2
  TEST_FILENAME_VAR = "test_filename_"
  CLASS_PEER_NAME = "Peer"
  PREFIX_PORT_NUMBER = "1111"

  STR0 = <<EOF
peer p0=localhost:11110;
peer p1=localhost:11111;
collection ext persistent local@p0(atom1*);
collection ext join_delegated@p0(atom1*);
fact local@p0(1);
fact local@p0(2);
fact local@p0(3);
fact local@p0(4);
rule join_delegated@p0($x):- local@p0($x),delegated@p1($x);
end
EOF

  STR1 = <<EOF
peer p0=localhost:11110;
peer p1=localhost:11111;
collection ext persistent delegated@p1(atom1*);
fact delegated@p1(0);
fact delegated@p1(3);
fact delegated@p1(4);
fact delegated@p1(5);
fact delegated@p1(6);
end
EOF

  def setup
    if @@first_test
      create_wlpeers_classes(NUMBER_OF_TEST_PG, CLASS_PEER_NAME)
      @@first_test=false
    end
    @wloptions = Struct.new :ip, :port, :wl_test
    (0..NUMBER_OF_TEST_PG-1).each do |i|
      eval("@#{TEST_FILENAME_VAR}#{i} = \"prog_#{create_name}_peer#{i}\"")
      eval("@tcoption#{i} = @wloptions.new \"localhost\",
 \"#{PREFIX_PORT_NUMBER}#{i}\",\"true\"")
    end
  end

  def teardown
    #    self.class.constants.each{ |item| p "#{item} : #{eval(item)}"if item=~/FILENAME/ }
    (0..NUMBER_OF_TEST_PG-1).each do |i|
      #      p Dir.entries((File.dirname("TEST_FILENAME_VAR#{i}"))).inspect+" in dir"
      #      p File.exist?(eval("TEST_FILENAME_VAR#{i}")).to_s+" exists?"
      #      p File.expand_path(File.dirname("TEST_FILENAME_VAR#{i}")).to_s+" dirname"
      eval("File.delete @#{TEST_FILENAME_VAR}#{i} if File.exist? @#{TEST_FILENAME_VAR}#{i}")
      #      p File.exist?(eval("TEST_FILENAME_VAR#{i}")).to_s+" exists?"
    end
  end

  def test_1_simple_delegation
    wl_peer = []
    (0..NUMBER_OF_TEST_PG-1).each do |i|
      wl_peer << eval("@@Peer#{i}.new(
\'p#{i}\',
STR#{i},
@#{TEST_FILENAME_VAR}#{i}, 
Hash[@tcoption#{i}.each_pair.to_a])")
    end
    
    # Insert here callback to push in queue q0 and q1 while test thread block on
    # pop as long as the wlbud thread has not finished his tick.
    #
    # Used to create a queue for synchronization of process.
    #
    # In test I use it as a callback block to evaluate and wait for pop in test
    # to ensure that underlying bud thread has finished tick
    #
    # XXX not really usefull since tick is already blocking 
    #
    q0 = Queue.new
    q1 = Queue.new
    block0 = lambda do | wlbudinstance, *options |
      q0.push true
    end
    block1 = lambda do | wlbudinstance, *options |
      q1.push true
    end
    wl_peer[0].register_wl_callback(:callback_step_end_tick, &block0)
    wl_peer[1].register_wl_callback(:callback_step_end_tick, &block1)
    
    #p "===wl_peer[1].tick 1==="
    wl_peer[1].tick
    q1.pop
    assert_equal 0, wl_peer[1].sbuffer.length
    assert_kind_of Bud::BudScratch, wl_peer[1].tables[:sbuffer]
    assert_equal 5, wl_peer[1].delegated_at_p1.length
    assert_equal [["0"], ["3"], ["4"], ["5"], ["6"]], wl_peer[1].delegated_at_p1.to_a.sort

    #p "===wl_peer[0].tick 1==="
    wl_peer[0].tick
    q0.pop
#    p "wait in delegation_1 to let EventMachine take the priority"
#    p EventMachine::connection_count
    # sleep 0.2 unless EventMachine::defers_finished?
    assert_equal 4, wl_peer[0].local_at_p0.length
    assert_equal [["1"], ["2"], ["3"], ["4"]], wl_peer[0].local_at_p0.to_a.sort
    assert_equal 4, wl_peer[0].sbuffer.length
    assert_equal [["1"], ["2"], ["3"], ["4"]], wl_peer[0].sbuffer.to_a.sort.map{ |obj| obj.fact }
    assert_equal 0, wl_peer[0].join_delegated_at_p0.length
    assert_equal [], wl_peer[0].join_delegated_at_p0.to_a.sort
    assert_equal 0, wl_peer[0].chan.length, "chan should be empty since peer1 is not suppose to receive something (storage and delta are empty)"
    assert_equal 0, wl_peer[0].chan.pending.length, "pending is always empty at the end of the tick"
    assert_equal 1, wl_peer[0].rules_to_delegate.length
    assert_equal 1, wl_peer[0].relation_to_declare.length
    assert_equal 1, wl_peer[0].relation_to_declare.values.first.length
    p wl_peer[0].relation_to_declare if $test_verbose
    new_declaration = wl_peer[0].relation_to_declare.values.first.to_s
    /(deleg.*)\(/ =~ new_declaration
    new_rel = Regexp.last_match(1).gsub('@', '_at_')
    assert_kind_of Bud::BudScratch, wl_peer[0].tables[new_rel.to_sym], "check the type of the newly created relation Table or Scratch"
    assert_equal 1, wl_peer[0].test_send_on_chan.length, "should send 1 packet"

    #p "===wl_peer[1].tick 2==="    
    old_nb_rel_peer2 = wl_peer[1].tables.length
    old_nb_rule_peer2 = wl_peer[1].tables[:t_rules].length
    # wait until the callback function receive_data in server.rb has been called
    cpt=0
    while wl_peer[1].inbound.empty?
      sleep 0.2
      cpt += 1
      if cpt>7
        assert(false, "it seems that peer1 is not receiving the message from peer 0")
      end
    end
    wl_peer[1].tick
    q1.pop    
    nb_rel_peer2 = wl_peer[1].tables.length
    nb_rule_peer2 = wl_peer[1].tables[:t_rules].length
    assert_equal 1, wl_peer[1].test_received_on_chan.length, "peer 1 is suppose to receive exaclty one packet"
    packet = wl_peer[1].test_received_on_chan.first
    assert_equal 1, packet.declarations.length, "only one new relation"
    assert_match new_declaration, packet.declarations.first, "new relation received is suppose to be #{new_rel}"

    assert_equal old_nb_rel_peer2 + 1, nb_rel_peer2, "one new relation should have been created"
    assert wl_peer[1].tables.keys.include?(new_rel.to_sym), "don't find the new relation #{new_rel}"
    assert_kind_of Bud::BudTable, wl_peer[1].tables[new_rel.to_sym], "check the type of the newly created relation Table or Scratch"
    assert_equal [["1"], ["2"], ["3"], ["4"]], wl_peer[1].tables[new_rel.to_sym].to_a.sort, "new collection doesn't have the good content "
    assert_equal old_nb_rule_peer2 + 1, nb_rule_peer2, "a new rule should have been created"
    assert_equal [["0"], ["3"], ["4"], ["5"], ["6"]], wl_peer[1].delegated_at_p1.to_a.sort, "delegated_at_p1 has not the expected content"

    if $test_verbose
      puts "should have one BLOOM rules now, see bloom method:"
      puts methname=wl_peer[1].class.instance_methods.select {|m| m =~ /^__bloom__.+$/}
      puts "ruby code inside:\n #{wl_peer[1].method(methname.first.to_sym).to_ruby}"
      puts "content of t_rules table:"
      wl_peer[1].tables[:t_rules].each { |v| puts " #{v.inspect}" }
    end
    assert_equal(1,
      wl_peer[1].class.instance_methods.select {|m| m =~ /^__bloom__.+$/}.length)
    assert_equal 2, wl_peer[1].sbuffer.length
    assert_equal [["3"], ["4"]], wl_peer[1].sbuffer.to_a.sort.map{ |obj| obj.fact }
    assert_equal 1, wl_peer[1].test_send_on_chan.length
    assert_equal 3, wl_peer[1].test_send_on_chan.first[1].length
    assert_equal 3, wl_peer[1].test_send_on_chan.first[1][2].length
    assert_equal 1, wl_peer[1].test_send_on_chan.first[1][2]["facts"].length
    assert_equal 2, wl_peer[1].test_send_on_chan.first[1][2]["facts"]["join_delegated_at_p0"].length
    # sort the content of the fact list to pass the next test since the content
    # could be in any order
    wl_peer[1].test_send_on_chan.first[1][2]["facts"]["join_delegated_at_p0"]=
      wl_peer[1].test_send_on_chan.first[1][2]["facts"]["join_delegated_at_p0"].to_a.sort
    assert_equal([["localhost:11110",["p1", "1",
            {"declarations"=>[],
              "facts"=>{"join_delegated_at_p0"=>[["3"], ["4"]]},
              "rules"=>[]}
          ]
        ]],
      wl_peer[1].test_send_on_chan)

    # Adding facts in a scratch via channel is useless since it will be erased
    # at the beginning of the tick.
    # TODO: Not so true check that
    #
    #p "===wl_peer[0].tick 2==="
    # wait until the callback function receive_data in server.rb has been called
    cpt=0
    while wl_peer[0].inbound.empty?
      sleep 0.2
      cpt += 1
      if cpt>7
        assert(false, "it seems that peer0 is not receiving the message from peer 1")
      end
    end
    wl_peer[0].tick;
    q0.pop
    assert_kind_of Array, wl_peer[0].test_received_on_chan
    assert_equal 1, wl_peer[0].test_received_on_chan.length
    assert_kind_of WLBud::WLPacketData, wl_peer[0].test_received_on_chan.first
    assert_equal 1, wl_peer[0].test_received_on_chan.first.facts.length
    #p wl_peer[0].test_received_on_chan.first.facts
    # sort the content of the fact list to pass the next test since the content
    # could be in any order
    wl_peer[0].test_received_on_chan.first.facts.each_pair{|k,v| v.sort!}
    assert_equal({"declarations"=>[],
        "facts"=>{"join_delegated_at_p0"=>[["3"], ["4"]]},
        "peer_name"=>"p1",
        "rules"=>[],
        "srcTimeStamp"=>1},
      WLTools::SerializeObjState.obj_to_hash(wl_peer[0].test_received_on_chan.first))

    assert_equal 0, wl_peer[0].join_delegated_at_p0.length, "there is no facts in the join since it is a scratch hence all facts written by a chan a erased at the beginning of eval"
    assert_equal [], wl_peer[0].join_delegated_at_p0.to_a.sort, "delegated_at_p1 has not the expected content"
  
    # TODO: change last and finish here (last is scratch without external updates)
    
  ensure
    wl_peer.each { |item| assert item.clear_rule_dir }
    if EventMachine::reactor_running?
      wl_peer[0].stop
      wl_peer[1].stop(true) # here I also stop EM to be clean
    end
  end
end

