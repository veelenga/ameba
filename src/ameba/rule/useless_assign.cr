module Ameba::Rule
  # A rule that disallows useless assignments.
  #
  # For example, this is considered invalid:
  #
  # ```
  # def method
  #   var = 1
  #   do_something
  # end
  # ```
  #
  # And has to be written as the following:
  #
  # ```
  # def method
  #   var = 1
  #   do_something(var)
  # end
  # ```
  #
  # YAML configuration example:
  #
  # ```
  # UselessAssign:
  #   Enabled: true
  # ```
  #
  struct UselessAssign < Base
    properties do
      description = "Disallows useless variable assignments"
    end

    MSG = "Useless assignment to variable `%s`"

    def test(source)
      AST::ScopeVisitor.new self, source
    end

    def test(source, node : Crystal::Def, scope : AST::Scope)
      scope.variables.each do |var|
        next if var.captured_by_block?
        var.assignments.each do |assign|
          next if assign.referenced?
          source.error self, assign.location, MSG % var.name
        end
      end
    end
  end
end