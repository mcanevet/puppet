class Puppet::Pops::Evaluator::CollectorTransformer

  def initialize
    @@query_visitor    ||= Puppet::Pops::Visitor.new(nil, "query", 1, 1)
    @@match_visitor    ||= Puppet::Pops::Visitor.new(nil, "match", 1, 1)
    @@evaluator        ||= Puppet::Pops::Evaluator::EvaluatorImpl.new
    @@compare_operator ||= Puppet::Pops::Evaluator::CompareOperator.new()
  end

  def transform(o, scope)
    raise ArgumentError, "Expected CollectExpression" unless o.is_a? Puppet::Pops::Model::CollectExpression

    raise "LHS is not a type" unless o.type_expr.is_a? Puppet::Pops::Model::QualifiedReference
    type = o.type_expr.value().downcase()

    if type == 'class'
      fail "Classes cannot be collected"
    end

    resource_type = scope.find_resource_type(type)
    fail "Resource type #{type} doesn't exist" unless resource_type

    adapter = Puppet::Pops::Adapters::SourcePosAdapter.adapt(o)
    line_num = adapter.line
    position = adapter.pos
    file_path = adapter.locator.file

    if !o.operations.empty?
      overrides = {
        :parameters => o.operations.map{ |x| to_3x_param(x).evaluate(scope)},
        :file       => file_path,
        :line       => [line_num, position],
        :source     => scope.source,
        :scope      => scope
      }
    end

    code = query_unless_nop(o.query, scope)

    case o.query
    when Puppet::Pops::Model::VirtualQuery
      newcoll = Puppet::Pops::Evaluator::Collectors::CatalogCollector.new(scope, resource_type.name, code, overrides)
    when Puppet::Pops::Model::ExportedQuery
      match = match_unless_nop(o.query, scope)
      newcoll = Puppet::Pops::Evaluator::Collectors::ExportedCollector.new(scope, resource_type.name, match, code, overrides)
    end

    scope.compiler.add_collection(newcoll)

    newcoll
  end

protected

  def query(o, scope)
    @@query_visitor.visit_this_1(self, o, scope)
  end

  def match(o, scope)
    @@match_visitor.visit_this_1(self, o, scope)
  end

  def query_unless_nop(query, scope)
    unless query.expr.nil? || query.expr.is_a?(Puppet::Pops::Model::Nop)
      query(query.expr, scope)
    end
  end

  def match_unless_nop(query, scope)
    unless query.expr.nil? || query.expr.is_a?(Puppet::Pops::Model::Nop)
      match(query.expr, scope)
    end
  end

  def query_AndExpression(o, scope)
    left_code = query(o.left_expr, scope)
    right_code = query(o.right_expr, scope)
    proc do |resource|
      left_code.call(resource) && right_code.call(resource)
    end
  end

  def query_OrExpression(o, scope)
    left_code = query(o.left_expr, scope)
    right_code = query(o.right_expr, scope)
    proc do |resource|
      left_code.call(resource) || right_code.call(resource)
    end
  end

  def query_ComparisonExpression(o, scope)
    left_code = query(o.left_expr, scope)
    right_code = query(o.right_expr, scope)

    case o.operator
    when :'=='
      if left_code == "tag"
        proc do |resource|
          resource.tagged?(right_code)
        end
      else
        proc do |resource|
          if (tmp = resource[left_code]).is_a?(Array)
            @@compare_operator.include?(tmp, right_code, scope)
          else
            @@compare_operator.equals(tmp, right_code)
          end
        end
      end
    when :'!='
      proc do |resource|
        !@@compare_operator.equals(resource[left_code], right_code)
      end
    end
  end

  def query_VariableExpression(o, scope)
    @@evaluator.evaluate(o, scope)
  end

  def query_LiteralBoolean(o, scope)
    @@evaluator.evaluate(o, scope)
  end

  def query_LiteralString(o, scope)
    @@evaluator.evaluate(o, scope)
  end

  def query_ConcatenatedString(o, scope)
    @@evaluator.evaluate(o, scope)
  end

  def query_LiteralNumber(o, scope)
    @@evaluator.evaluate(o, scope)
  end

  def query_QualifiedName(o, scope)
    @@evaluator.evaluate(o, scope)
  end

  def query_ParenthesizedExpression(o, scope)
   query(o.expr, scope)
  end

  def query_Object(o, scope)
    raise ArgumentError, "Cannot transform object of class #{o.class}"
  end

  def match_AndExpression(o, scope)
    left_match = match(o.left_expr, scope)
    right_match = match(o.right_expr, scope)
    return [left_match, 'and', right_match]
  end

  def match_OrExpression(o, scope)
    left_match = match(o.left_expr, scope)
    right_match = match(o.right_expr, scope)
    return [left_match, 'or', right_match]
  end

  def match_ComparisonExpression(o, scope)
    left_match = match(o.left_expr, scope)
    right_match = match(o.right_expr, scope)
    return [left_match, o.operator.to_s, right_match]
  end

  def match_VariableExpression(o, scope)
    @@evaluator.evaluate(o, scope)
  end

  def match_LiteralBoolean(o, scope)
    @@evaluator.evaluate(o, scope)
  end

  def match_LiteralString(o, scope)
    @@evaluator.evaluate(o, scope)
  end

  def match_ConcatenatedString(o, scope)
    @@evaluator.evaluate(o, scope)
  end

  def match_LiteralNumber(o, scope)
    @@evaluator.evaluate(o, scope)
  end

  def match_QualifiedName(o, scope)
    @@evaluator.evaluate(o, scope)
  end

  def match_ParenthesizedExpression(o, scope)
   match(o.expr, scope)
  end

  def match_Object(o, scope)
    raise ArgumentError, "Cannot transform object of class #{o.class}"
  end

  # Produces (name => expr) or (name +> expr)
  def to_3x_param(o)
    bridge = Puppet::Parser::AST::PopsBridge::Expression.new(:value => o.value_expr)
    args = { :value => bridge }
    args[:add] = true if o.operator == :'+>'
    args[:param] = o.attribute_name
    args= Puppet::Pops::Model::AstTransformer.new().merge_location(args, o)
    Puppet::Parser::AST::ResourceParam.new(args)
  end
end
