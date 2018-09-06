require "./base_visitor"

module Ameba::AST
  # AST Visitor that traverses the source and constructs scopes.
  class ScopeVisitor < BaseVisitor
    SUPER = "super"
    # List of special top level macros that use assignments
    # as the macro arguments thus such arguments are not treated as assignments.
    #
    # For example:
    #
    # ```
    # bar = 1
    # record Foo, bar = 2 # this is not an assignment
    # bar                 # => 1
    # ```
    SPECIAL_TOP_LEVEL_MACROS = %w(
      record
    )

    @current_scope : Scope

    def initialize(@rule, @source)
      @current_scope = Scope.new(@source.ast) # top level scope
      @source.ast.accept self
    end

    private def on_scope_enter(node)
      @current_scope = Scope.new(node, @current_scope)
    end

    private def on_scope_end(node)
      @rule.test @source, node, @current_scope

      # go up, if this is not a top level scope
      if outer_scope = @current_scope.outer_scope
        @current_scope = outer_scope
      end
    end

    private def on_assign_end(target, node)
      target.is_a?(Crystal::Var) && @current_scope.assign_variable(target.name, node)
    end

    # :nodoc:
    def end_visit(node : Crystal::ASTNode)
      on_scope_end(node) if @current_scope.eql?(node)
    end

    # :nodoc:
    def visit(node : Crystal::ClassDef)
      on_scope_enter(node)
    end

    # :nodoc:
    def visit(node : Crystal::ModuleDef)
      on_scope_enter(node)
    end

    # :nodoc:
    def visit(node : Crystal::LibDef)
      on_scope_enter(node)
    end

    # :nodoc:
    def visit(node : Crystal::FunDef)
      on_scope_enter(node)
    end

    # :nodoc:
    def visit(node : Crystal::TypeDef)
      on_scope_enter(node)
    end

    # :nodoc:
    def visit(node : Crystal::CStructOrUnionDef)
      on_scope_enter(node)
    end

    # :nodoc:
    def visit(node : Crystal::Def)
      node.name == "->" || on_scope_enter(node)
    end

    # :nodoc:
    def visit(node : Crystal::ProcLiteral)
      on_scope_enter(node)
    end

    # :nodoc:
    def visit(node : Crystal::Block)
      on_scope_enter(node)
    end

    # :nodoc:
    def visit(node : Crystal::Macro)
      on_scope_enter(node)
    end

    @current_assign : Crystal::ASTNode?

    # :nodoc:
    def visit(node : Crystal::Assign | Crystal::OpAssign | Crystal::MultiAssign | Crystal::UninitializedVar)
      @current_assign = node
    end

    # :nodoc:
    def end_visit(node : Crystal::Assign | Crystal::OpAssign)
      on_assign_end(node.target, node)
      @current_assign = nil
      on_scope_end(node) if @current_scope.eql?(node)
    end

    # :nodoc:
    def end_visit(node : Crystal::MultiAssign)
      node.targets.each { |target| on_assign_end(target, node) }
      @current_assign = nil
      on_scope_end(node) if @current_scope.eql?(node)
    end

    # :nodoc:
    def end_visit(node : Crystal::UninitializedVar)
      on_assign_end(node.var, node)
      @current_assign = nil
      on_scope_end(node) if @current_scope.eql?(node)
    end

    # :nodoc:
    def visit(node : Crystal::TypeDeclaration)
      if !@current_scope.type_definition? && (var = node.var).is_a?(Crystal::Var)
        @current_scope.add_variable var
      end
    end

    # :nodoc:
    def visit(node : Crystal::Arg)
      @current_scope.add_argument node
    end

    # :nodoc:
    def visit(node : Crystal::Var)
      variable = @current_scope.find_variable node.name

      if @current_scope.arg?(node) # node is an argument
        @current_scope.add_argument(node)
      elsif variable.nil? && @current_assign # node is a variable
        @current_scope.add_variable(node)
      elsif variable # node is a reference
        reference = variable.reference node, @current_scope
        if @current_assign.is_a?(Crystal::OpAssign) || !reference.target_of?(@current_assign)
          variable.reference_assignments!
        end
      end
    end

    # :nodoc:
    def visit(node : Crystal::Call)
      case @current_scope
      when .def?
        if node.name == SUPER && node.args.empty?
          @current_scope.arguments.each do |arg|
            variable = arg.variable
            variable.reference(variable.node, @current_scope).explicit = false
          end
        end
      when .top_level?
        return false if SPECIAL_TOP_LEVEL_MACROS.includes?(node.name)
      end

      true
    end
  end
end
