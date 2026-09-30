/// A tiny boolean expression language used by rules to describe when a
/// piece of liturgy is said, e.g. `roshChodesh || cholHamoed`,
/// `!shabbat && (aseretYemeiTeshuva || publicFast)`, `omerDay == 12`,
/// `dow in [1, 4]`.
///
/// Grammar:
///   expr    := or
///   or      := and ('||' and)*
///   and     := unary ('&&' unary)*
///   unary   := '!' unary | cmp
///   cmp     := primary (('=='|'!='|'<'|'<='|'>'|'>=') primary | 'in' list)?
///   primary := IDENT | NUMBER | 'true' | 'false' | '(' expr ')'
///   list    := '[' (primary (',' primary)*)? ']'
library;

/// Variables available to conditions; values are `bool` or `num`.
typedef ConditionEnv = Map<String, Object>;

sealed class Condition {
  const Condition();

  /// Evaluates to a bool. Unknown identifiers evaluate to false / 0 and are
  /// reported through [unknown] when provided.
  bool eval(ConditionEnv env, [Set<String>? unknown]) =>
      _truthy(_value(env, unknown));

  Object _value(ConditionEnv env, Set<String>? unknown);

  /// Identifiers referenced by this condition.
  Set<String> get identifiers;

  static final Map<String, Condition> _cache = {};

  /// Parses (and caches) a condition expression.
  static Condition parse(String source) =>
      _cache.putIfAbsent(source, () => _Parser(source).parse());

  static const Condition always = _Lit(true);
  static const Condition never = _Lit(false);

  Condition and(Condition other) => _Bin('&&', this, other);
  Condition or(Condition other) => _Bin('||', this, other);
  Condition not() => _Not(this);
}

bool _truthy(Object v) => v is bool ? v : (v is num ? v != 0 : true);

class _Lit extends Condition {
  final Object value;
  const _Lit(this.value);
  @override
  Object _value(ConditionEnv env, Set<String>? unknown) => value;
  @override
  Set<String> get identifiers => const {};
  @override
  String toString() => '$value';
}

class _Var extends Condition {
  final String name;
  const _Var(this.name);
  @override
  Object _value(ConditionEnv env, Set<String>? unknown) {
    final v = env[name];
    if (v == null) {
      unknown?.add(name);
      return false;
    }
    return v;
  }

  @override
  Set<String> get identifiers => {name};
  @override
  String toString() => name;
}

class _Not extends Condition {
  final Condition inner;
  const _Not(this.inner);
  @override
  Object _value(ConditionEnv env, Set<String>? unknown) => !inner.eval(env, unknown);
  @override
  Set<String> get identifiers => inner.identifiers;
  @override
  String toString() => '!($inner)';
}

class _Bin extends Condition {
  final String op;
  final Condition l;
  final Condition r;
  const _Bin(this.op, this.l, this.r);

  @override
  Object _value(ConditionEnv env, Set<String>? unknown) {
    switch (op) {
      case '&&':
        return l.eval(env, unknown) && r.eval(env, unknown);
      case '||':
        return l.eval(env, unknown) || r.eval(env, unknown);
    }
    final a = l._value(env, unknown);
    final b = r._value(env, unknown);
    num n(Object x) => x is num ? x : (x == true ? 1 : 0);
    switch (op) {
      case '==':
        return n(a) == n(b);
      case '!=':
        return n(a) != n(b);
      case '<':
        return n(a) < n(b);
      case '<=':
        return n(a) <= n(b);
      case '>':
        return n(a) > n(b);
      case '>=':
        return n(a) >= n(b);
    }
    throw StateError('bad op $op');
  }

  @override
  Set<String> get identifiers => {...l.identifiers, ...r.identifiers};
  @override
  String toString() => '($l $op $r)';
}

class _In extends Condition {
  final Condition l;
  final List<Condition> items;
  const _In(this.l, this.items);
  @override
  Object _value(ConditionEnv env, Set<String>? unknown) {
    final v = l._value(env, unknown);
    return items.any((i) => i._value(env, unknown) == v);
  }

  @override
  Set<String> get identifiers => {...l.identifiers, for (final i in items) ...i.identifiers};
  @override
  String toString() => '($l in $items)';
}

class ConditionParseException implements Exception {
  final String message;
  final String source;
  final int offset;
  ConditionParseException(this.message, this.source, this.offset);
  @override
  String toString() => 'ConditionParseException: $message at $offset in "$source"';
}

class _Parser {
  final String src;
  int pos = 0;
  _Parser(this.src);

  Condition parse() {
    final c = _or();
    _ws();
    if (pos != src.length) _fail('unexpected "${src.substring(pos)}"');
    return c;
  }

  Never _fail(String msg) => throw ConditionParseException(msg, src, pos);

  void _ws() {
    while (pos < src.length && ' \t\n\r'.contains(src[pos])) {
      pos++;
    }
  }

  bool _eat(String tok) {
    _ws();
    if (src.startsWith(tok, pos)) {
      pos += tok.length;
      return true;
    }
    return false;
  }

  Condition _or() {
    var l = _and();
    while (_eat('||')) {
      l = _Bin('||', l, _and());
    }
    return l;
  }

  Condition _and() {
    var l = _unary();
    while (_eat('&&')) {
      l = _Bin('&&', l, _unary());
    }
    return l;
  }

  Condition _unary() {
    _ws();
    if (pos < src.length && src[pos] == '!' && !src.startsWith('!=', pos)) {
      pos++;
      return _Not(_unary());
    }
    return _cmp();
  }

  Condition _cmp() {
    final l = _primary();
    for (final op in const ['==', '!=', '<=', '>=', '<', '>']) {
      if (_eat(op)) return _Bin(op, l, _primary());
    }
    _ws();
    if (src.startsWith('in', pos) && (pos + 2 >= src.length || !_isIdent(src[pos + 2]))) {
      pos += 2;
      if (!_eat('[')) _fail('expected [');
      final items = <Condition>[];
      if (!_eat(']')) {
        do {
          items.add(_primary());
        } while (_eat(','));
        if (!_eat(']')) _fail('expected ]');
      }
      return _In(l, items);
    }
    return l;
  }

  static bool _isIdent(String c) => RegExp(r'[A-Za-z0-9_]').hasMatch(c);

  Condition _primary() {
    _ws();
    if (_eat('(')) {
      final c = _or();
      if (!_eat(')')) _fail('expected )');
      return c;
    }
    final m = RegExp(r'-?\d+(\.\d+)?|[A-Za-z_][A-Za-z0-9_]*').matchAsPrefix(src, pos);
    if (m == null) _fail('expected identifier or number');
    pos = m.end;
    final t = m[0]!;
    if (t == 'true') return const _Lit(true);
    if (t == 'false') return const _Lit(false);
    final n = num.tryParse(t);
    if (n != null) return _Lit(n);
    return _Var(t);
  }
}
