# frozen_string_literal: true

require_relative 'lib/lalrrb.rb'

fsm = Lalrrb::FSM.new
s1 = fsm.state(:s1)
s2 = fsm.state(:s2)
s3 = fsm.state(:s3, accept: true)
s4 = fsm.state(:s4)
s5 = fsm.state(:s5)
s6 = fsm.state(:s6)
s7 = fsm.state(:s7)
s8 = fsm.state(:s8, accept: true)
s9 = fsm.state(:s9)
s10 = fsm.state(:s10)
s11 = fsm.state(:s11)
s12 = fsm.state(:s12)
s13 = fsm.state(:s13, accept: true)

fsm.edge(s1, s2, 'i')
fsm.edge(s2, s3, 'f')
fsm.edge(s1, s4)
fsm.edge(s4, s5, /[a-z]/)
fsm.edge(s5, s8)
fsm.edge(s8, s6)
fsm.edge(s6, s7, /[a-z]/)
fsm.edge(s6, s7, /[0-9]/)
fsm.edge(s7, s8)
fsm.edge(s1, s9)
fsm.edge(s9, s10, /[0-9]/)
fsm.edge(s10, s13)
fsm.edge(s13, s11)
fsm.edge(s11, s12, /[0-9]/)
fsm.edge(s12, s13)

fsm.graphviz.output(png: "fsm.png")
puts fsm.table
