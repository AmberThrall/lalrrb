# frozen_string_literal: true

require_relative '../lib/lalrrb'
require_relative '../lib/lalrrb/abnf'

POSTAL_GRAMMAR = %(
  %token(SP, " ")
  %token(CRLF, "\\r\\n")
  %token(ALPHA, %x41-5A / %x61-7A) ; A-Z / a-z
  %token(DIGIT, %x30-39)    ; 0-9
  %token(VCHAR, %x21-7E)
  %start(postal-address)

  postal-address   = name-part street zip-part

  name-part        = *(personal-part SP) last-name [SP suffix] CRLF
  name-part        =/ personal-part CRLF

  personal-part    = first-name / (initial ".")
  first-name       = *ALPHA
  initial          = ALPHA
  last-name        = *ALPHA
  suffix           = ("Jr." / "Sr." / 1*1("I" / "V" / "X"))

  street           = [apt SP] house-num SP street-name CRLF
  apt              = 1*4DIGIT
  house-num        = 1*8(DIGIT / alpha)
  street-name      = 1*VCHAR

  zip-part         = town-name "," SP state 1*2SP zip-code CRLF
  town-name        = 1*(ALPHA / SP)
  state            = 2ALPHA
  zip-code         = 5DIGIT ["-" 4DIGIT]
)

root, log = Lalrrb::Grammars::ABNF.parse(POSTAL_GRAMMAR)
log.save("postal-address.csv")
root.search(:c_nl).each { |node| node.delete(keep_descendents: false) }
root.graphviz.output(png: "postal-address.png")
