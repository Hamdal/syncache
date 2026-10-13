// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drift_database.dart';

// ignore_for_file: type=lint
class $CacheEntriesTable extends CacheEntries
    with TableInfo<$CacheEntriesTable, CacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _storedAtMeta =
      const VerificationMeta('storedAt');
  @override
  late final GeneratedColumn<int> storedAt = GeneratedColumn<int>(
      'stored_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _ttlMsMeta = const VerificationMeta('ttlMs');
  @override
  late final GeneratedColumn<int> ttlMs = GeneratedColumn<int>(
      'ttl_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
      'etag', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastModifiedMeta =
      const VerificationMeta('lastModified');
  @override
  late final GeneratedColumn<int> lastModified = GeneratedColumn<int>(
      'last_modified', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [key, value, version, storedAt, ttlMs, etag, lastModified];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache';
  @override
  VerificationContext validateIntegrity(Insertable<CacheEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('stored_at')) {
      context.handle(_storedAtMeta,
          storedAt.isAcceptableOrUnknown(data['stored_at']!, _storedAtMeta));
    } else if (isInserting) {
      context.missing(_storedAtMeta);
    }
    if (data.containsKey('ttl_ms')) {
      context.handle(
          _ttlMsMeta, ttlMs.isAcceptableOrUnknown(data['ttl_ms']!, _ttlMsMeta));
    }
    if (data.containsKey('etag')) {
      context.handle(
          _etagMeta, etag.isAcceptableOrUnknown(data['etag']!, _etagMeta));
    }
    if (data.containsKey('last_modified')) {
      context.handle(
          _lastModifiedMeta,
          lastModified.isAcceptableOrUnknown(
              data['last_modified']!, _lastModifiedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheEntry(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      storedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}stored_at'])!,
      ttlMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ttl_ms']),
      etag: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}etag']),
      lastModified: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_modified']),
    );
  }

  @override
  $CacheEntriesTable createAlias(String alias) {
    return $CacheEntriesTable(attachedDatabase, alias);
  }
}

class CacheEntry extends DataClass implements Insertable<CacheEntry> {
  /// The cache key (primary key).
  final String key;

  /// The JSON-encoded cached value.
  final String value;

  /// Version of this entry, used for conflict detection.
  final int version;

  /// When the entry was stored (epoch milliseconds).
  final int storedAt;

  /// Time-to-live in milliseconds, or `null` for entries that never expire
  /// based on time.
  final int? ttlMs;

  /// HTTP ETag for conditional requests, if any.
  final String? etag;

  /// HTTP last-modified timestamp (epoch milliseconds), if any.
  final int? lastModified;
  const CacheEntry(
      {required this.key,
      required this.value,
      required this.version,
      required this.storedAt,
      this.ttlMs,
      this.etag,
      this.lastModified});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['version'] = Variable<int>(version);
    map['stored_at'] = Variable<int>(storedAt);
    if (!nullToAbsent || ttlMs != null) {
      map['ttl_ms'] = Variable<int>(ttlMs);
    }
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    if (!nullToAbsent || lastModified != null) {
      map['last_modified'] = Variable<int>(lastModified);
    }
    return map;
  }

  CacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return CacheEntriesCompanion(
      key: Value(key),
      value: Value(value),
      version: Value(version),
      storedAt: Value(storedAt),
      ttlMs:
          ttlMs == null && nullToAbsent ? const Value.absent() : Value(ttlMs),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      lastModified: lastModified == null && nullToAbsent
          ? const Value.absent()
          : Value(lastModified),
    );
  }

  factory CacheEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheEntry(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      version: serializer.fromJson<int>(json['version']),
      storedAt: serializer.fromJson<int>(json['storedAt']),
      ttlMs: serializer.fromJson<int?>(json['ttlMs']),
      etag: serializer.fromJson<String?>(json['etag']),
      lastModified: serializer.fromJson<int?>(json['lastModified']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'version': serializer.toJson<int>(version),
      'storedAt': serializer.toJson<int>(storedAt),
      'ttlMs': serializer.toJson<int?>(ttlMs),
      'etag': serializer.toJson<String?>(etag),
      'lastModified': serializer.toJson<int?>(lastModified),
    };
  }

  CacheEntry copyWith(
          {String? key,
          String? value,
          int? version,
          int? storedAt,
          Value<int?> ttlMs = const Value.absent(),
          Value<String?> etag = const Value.absent(),
          Value<int?> lastModified = const Value.absent()}) =>
      CacheEntry(
        key: key ?? this.key,
        value: value ?? this.value,
        version: version ?? this.version,
        storedAt: storedAt ?? this.storedAt,
        ttlMs: ttlMs.present ? ttlMs.value : this.ttlMs,
        etag: etag.present ? etag.value : this.etag,
        lastModified:
            lastModified.present ? lastModified.value : this.lastModified,
      );
  CacheEntry copyWithCompanion(CacheEntriesCompanion data) {
    return CacheEntry(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      version: data.version.present ? data.version.value : this.version,
      storedAt: data.storedAt.present ? data.storedAt.value : this.storedAt,
      ttlMs: data.ttlMs.present ? data.ttlMs.value : this.ttlMs,
      etag: data.etag.present ? data.etag.value : this.etag,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntry(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('version: $version, ')
          ..write('storedAt: $storedAt, ')
          ..write('ttlMs: $ttlMs, ')
          ..write('etag: $etag, ')
          ..write('lastModified: $lastModified')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(key, value, version, storedAt, ttlMs, etag, lastModified);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheEntry &&
          other.key == this.key &&
          other.value == this.value &&
          other.version == this.version &&
          other.storedAt == this.storedAt &&
          other.ttlMs == this.ttlMs &&
          other.etag == this.etag &&
          other.lastModified == this.lastModified);
}

class CacheEntriesCompanion extends UpdateCompanion<CacheEntry> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> version;
  final Value<int> storedAt;
  final Value<int?> ttlMs;
  final Value<String?> etag;
  final Value<int?> lastModified;
  final Value<int> rowid;
  const CacheEntriesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.version = const Value.absent(),
    this.storedAt = const Value.absent(),
    this.ttlMs = const Value.absent(),
    this.etag = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheEntriesCompanion.insert({
    required String key,
    required String value,
    required int version,
    required int storedAt,
    this.ttlMs = const Value.absent(),
    this.etag = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value),
        version = Value(version),
        storedAt = Value(storedAt);
  static Insertable<CacheEntry> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? version,
    Expression<int>? storedAt,
    Expression<int>? ttlMs,
    Expression<String>? etag,
    Expression<int>? lastModified,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (version != null) 'version': version,
      if (storedAt != null) 'stored_at': storedAt,
      if (ttlMs != null) 'ttl_ms': ttlMs,
      if (etag != null) 'etag': etag,
      if (lastModified != null) 'last_modified': lastModified,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheEntriesCompanion copyWith(
      {Value<String>? key,
      Value<String>? value,
      Value<int>? version,
      Value<int>? storedAt,
      Value<int?>? ttlMs,
      Value<String?>? etag,
      Value<int?>? lastModified,
      Value<int>? rowid}) {
    return CacheEntriesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      version: version ?? this.version,
      storedAt: storedAt ?? this.storedAt,
      ttlMs: ttlMs ?? this.ttlMs,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (storedAt.present) {
      map['stored_at'] = Variable<int>(storedAt.value);
    }
    if (ttlMs.present) {
      map['ttl_ms'] = Variable<int>(ttlMs.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<int>(lastModified.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntriesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('version: $version, ')
          ..write('storedAt: $storedAt, ')
          ..write('ttlMs: $ttlMs, ')
          ..write('etag: $etag, ')
          ..write('lastModified: $lastModified, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CacheTagsTable extends CacheTags
    with TableInfo<$CacheTagsTable, CacheTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tagMeta = const VerificationMeta('tag');
  @override
  late final GeneratedColumn<String> tag = GeneratedColumn<String>(
      'tag', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, tag];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_tags';
  @override
  VerificationContext validateIntegrity(Insertable<CacheTag> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('tag')) {
      context.handle(
          _tagMeta, tag.isAcceptableOrUnknown(data['tag']!, _tagMeta));
    } else if (isInserting) {
      context.missing(_tagMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key, tag};
  @override
  CacheTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheTag(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      tag: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tag'])!,
    );
  }

  @override
  $CacheTagsTable createAlias(String alias) {
    return $CacheTagsTable(attachedDatabase, alias);
  }
}

class CacheTag extends DataClass implements Insertable<CacheTag> {
  /// The cache key this tag is associated with.
  final String key;

  /// The tag.
  final String tag;
  const CacheTag({required this.key, required this.tag});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['tag'] = Variable<String>(tag);
    return map;
  }

  CacheTagsCompanion toCompanion(bool nullToAbsent) {
    return CacheTagsCompanion(
      key: Value(key),
      tag: Value(tag),
    );
  }

  factory CacheTag.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheTag(
      key: serializer.fromJson<String>(json['key']),
      tag: serializer.fromJson<String>(json['tag']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'tag': serializer.toJson<String>(tag),
    };
  }

  CacheTag copyWith({String? key, String? tag}) => CacheTag(
        key: key ?? this.key,
        tag: tag ?? this.tag,
      );
  CacheTag copyWithCompanion(CacheTagsCompanion data) {
    return CacheTag(
      key: data.key.present ? data.key.value : this.key,
      tag: data.tag.present ? data.tag.value : this.tag,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheTag(')
          ..write('key: $key, ')
          ..write('tag: $tag')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, tag);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheTag && other.key == this.key && other.tag == this.tag);
}

class CacheTagsCompanion extends UpdateCompanion<CacheTag> {
  final Value<String> key;
  final Value<String> tag;
  final Value<int> rowid;
  const CacheTagsCompanion({
    this.key = const Value.absent(),
    this.tag = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheTagsCompanion.insert({
    required String key,
    required String tag,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        tag = Value(tag);
  static Insertable<CacheTag> custom({
    Expression<String>? key,
    Expression<String>? tag,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (tag != null) 'tag': tag,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheTagsCompanion copyWith(
      {Value<String>? key, Value<String>? tag, Value<int>? rowid}) {
    return CacheTagsCompanion(
      key: key ?? this.key,
      tag: tag ?? this.tag,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (tag.present) {
      map['tag'] = Variable<String>(tag.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheTagsCompanion(')
          ..write('key: $key, ')
          ..write('tag: $tag, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MutationOutboxEntriesTable extends MutationOutboxEntries
    with TableInfo<$MutationOutboxEntriesTable, MutationOutboxRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MutationOutboxEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
      'seq', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _queuedAtMeta =
      const VerificationMeta('queuedAt');
  @override
  late final GeneratedColumn<int> queuedAt = GeneratedColumn<int>(
      'queued_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _optimisticSnapshotMeta =
      const VerificationMeta('optimisticSnapshot');
  @override
  late final GeneratedColumn<String> optimisticSnapshot =
      GeneratedColumn<String>('optimistic_snapshot', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, key, seq, payload, queuedAt, optimisticSnapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mutation_outbox';
  @override
  VerificationContext validateIntegrity(
      Insertable<MutationOutboxRecord> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
          _seqMeta, seq.isAcceptableOrUnknown(data['seq']!, _seqMeta));
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('queued_at')) {
      context.handle(_queuedAtMeta,
          queuedAt.isAcceptableOrUnknown(data['queued_at']!, _queuedAtMeta));
    } else if (isInserting) {
      context.missing(_queuedAtMeta);
    }
    if (data.containsKey('optimistic_snapshot')) {
      context.handle(
          _optimisticSnapshotMeta,
          optimisticSnapshot.isAcceptableOrUnknown(
              data['optimistic_snapshot']!, _optimisticSnapshotMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MutationOutboxRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MutationOutboxRecord(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      seq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}seq'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      queuedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}queued_at'])!,
      optimisticSnapshot: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}optimistic_snapshot']),
    );
  }

  @override
  $MutationOutboxEntriesTable createAlias(String alias) {
    return $MutationOutboxEntriesTable(attachedDatabase, alias);
  }
}

class MutationOutboxRecord extends DataClass
    implements Insertable<MutationOutboxRecord> {
  /// Stable mutation id (primary key).
  final String id;

  /// The cache key this mutation affects.
  final String key;

  /// Monotonic enqueue order; `loadAll` returns rows ordered by this column.
  final int seq;

  /// The caller-supplied JSON payload of the mutation.
  final String payload;

  /// When the mutation was enqueued (epoch milliseconds).
  final int queuedAt;

  /// JSON-encoded optimistic snapshot, or `null` when the caller opted out.
  ///
  /// Persisting this lets recovery replay the *exact* pre-death optimistic
  /// value, matching the behavior of the Hive outbox.
  final String? optimisticSnapshot;
  const MutationOutboxRecord(
      {required this.id,
      required this.key,
      required this.seq,
      required this.payload,
      required this.queuedAt,
      this.optimisticSnapshot});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['key'] = Variable<String>(key);
    map['seq'] = Variable<int>(seq);
    map['payload'] = Variable<String>(payload);
    map['queued_at'] = Variable<int>(queuedAt);
    if (!nullToAbsent || optimisticSnapshot != null) {
      map['optimistic_snapshot'] = Variable<String>(optimisticSnapshot);
    }
    return map;
  }

  MutationOutboxEntriesCompanion toCompanion(bool nullToAbsent) {
    return MutationOutboxEntriesCompanion(
      id: Value(id),
      key: Value(key),
      seq: Value(seq),
      payload: Value(payload),
      queuedAt: Value(queuedAt),
      optimisticSnapshot: optimisticSnapshot == null && nullToAbsent
          ? const Value.absent()
          : Value(optimisticSnapshot),
    );
  }

  factory MutationOutboxRecord.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MutationOutboxRecord(
      id: serializer.fromJson<String>(json['id']),
      key: serializer.fromJson<String>(json['key']),
      seq: serializer.fromJson<int>(json['seq']),
      payload: serializer.fromJson<String>(json['payload']),
      queuedAt: serializer.fromJson<int>(json['queuedAt']),
      optimisticSnapshot:
          serializer.fromJson<String?>(json['optimisticSnapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'key': serializer.toJson<String>(key),
      'seq': serializer.toJson<int>(seq),
      'payload': serializer.toJson<String>(payload),
      'queuedAt': serializer.toJson<int>(queuedAt),
      'optimisticSnapshot': serializer.toJson<String?>(optimisticSnapshot),
    };
  }

  MutationOutboxRecord copyWith(
          {String? id,
          String? key,
          int? seq,
          String? payload,
          int? queuedAt,
          Value<String?> optimisticSnapshot = const Value.absent()}) =>
      MutationOutboxRecord(
        id: id ?? this.id,
        key: key ?? this.key,
        seq: seq ?? this.seq,
        payload: payload ?? this.payload,
        queuedAt: queuedAt ?? this.queuedAt,
        optimisticSnapshot: optimisticSnapshot.present
            ? optimisticSnapshot.value
            : this.optimisticSnapshot,
      );
  MutationOutboxRecord copyWithCompanion(MutationOutboxEntriesCompanion data) {
    return MutationOutboxRecord(
      id: data.id.present ? data.id.value : this.id,
      key: data.key.present ? data.key.value : this.key,
      seq: data.seq.present ? data.seq.value : this.seq,
      payload: data.payload.present ? data.payload.value : this.payload,
      queuedAt: data.queuedAt.present ? data.queuedAt.value : this.queuedAt,
      optimisticSnapshot: data.optimisticSnapshot.present
          ? data.optimisticSnapshot.value
          : this.optimisticSnapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MutationOutboxRecord(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('seq: $seq, ')
          ..write('payload: $payload, ')
          ..write('queuedAt: $queuedAt, ')
          ..write('optimisticSnapshot: $optimisticSnapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, key, seq, payload, queuedAt, optimisticSnapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MutationOutboxRecord &&
          other.id == this.id &&
          other.key == this.key &&
          other.seq == this.seq &&
          other.payload == this.payload &&
          other.queuedAt == this.queuedAt &&
          other.optimisticSnapshot == this.optimisticSnapshot);
}

class MutationOutboxEntriesCompanion
    extends UpdateCompanion<MutationOutboxRecord> {
  final Value<String> id;
  final Value<String> key;
  final Value<int> seq;
  final Value<String> payload;
  final Value<int> queuedAt;
  final Value<String?> optimisticSnapshot;
  final Value<int> rowid;
  const MutationOutboxEntriesCompanion({
    this.id = const Value.absent(),
    this.key = const Value.absent(),
    this.seq = const Value.absent(),
    this.payload = const Value.absent(),
    this.queuedAt = const Value.absent(),
    this.optimisticSnapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MutationOutboxEntriesCompanion.insert({
    required String id,
    required String key,
    required int seq,
    required String payload,
    required int queuedAt,
    this.optimisticSnapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        key = Value(key),
        seq = Value(seq),
        payload = Value(payload),
        queuedAt = Value(queuedAt);
  static Insertable<MutationOutboxRecord> custom({
    Expression<String>? id,
    Expression<String>? key,
    Expression<int>? seq,
    Expression<String>? payload,
    Expression<int>? queuedAt,
    Expression<String>? optimisticSnapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (key != null) 'key': key,
      if (seq != null) 'seq': seq,
      if (payload != null) 'payload': payload,
      if (queuedAt != null) 'queued_at': queuedAt,
      if (optimisticSnapshot != null) 'optimistic_snapshot': optimisticSnapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MutationOutboxEntriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? key,
      Value<int>? seq,
      Value<String>? payload,
      Value<int>? queuedAt,
      Value<String?>? optimisticSnapshot,
      Value<int>? rowid}) {
    return MutationOutboxEntriesCompanion(
      id: id ?? this.id,
      key: key ?? this.key,
      seq: seq ?? this.seq,
      payload: payload ?? this.payload,
      queuedAt: queuedAt ?? this.queuedAt,
      optimisticSnapshot: optimisticSnapshot ?? this.optimisticSnapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (queuedAt.present) {
      map['queued_at'] = Variable<int>(queuedAt.value);
    }
    if (optimisticSnapshot.present) {
      map['optimistic_snapshot'] = Variable<String>(optimisticSnapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MutationOutboxEntriesCompanion(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('seq: $seq, ')
          ..write('payload: $payload, ')
          ..write('queuedAt: $queuedAt, ')
          ..write('optimisticSnapshot: $optimisticSnapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SyncacheDriftDatabase extends GeneratedDatabase {
  _$SyncacheDriftDatabase(QueryExecutor e) : super(e);
  $SyncacheDriftDatabaseManager get managers =>
      $SyncacheDriftDatabaseManager(this);
  late final $CacheEntriesTable cacheEntries = $CacheEntriesTable(this);
  late final $CacheTagsTable cacheTags = $CacheTagsTable(this);
  late final $MutationOutboxEntriesTable mutationOutboxEntries =
      $MutationOutboxEntriesTable(this);
  late final Index cacheTagsTagIdx = Index('cache_tags_tag_idx',
      'CREATE INDEX cache_tags_tag_idx ON cache_tags (tag)');
  late final Index mutationOutboxSeqIdx = Index('mutation_outbox_seq_idx',
      'CREATE INDEX mutation_outbox_seq_idx ON mutation_outbox (seq)');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        cacheEntries,
        cacheTags,
        mutationOutboxEntries,
        cacheTagsTagIdx,
        mutationOutboxSeqIdx
      ];
}

typedef $$CacheEntriesTableCreateCompanionBuilder = CacheEntriesCompanion
    Function({
  required String key,
  required String value,
  required int version,
  required int storedAt,
  Value<int?> ttlMs,
  Value<String?> etag,
  Value<int?> lastModified,
  Value<int> rowid,
});
typedef $$CacheEntriesTableUpdateCompanionBuilder = CacheEntriesCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<int> version,
  Value<int> storedAt,
  Value<int?> ttlMs,
  Value<String?> etag,
  Value<int?> lastModified,
  Value<int> rowid,
});

class $$CacheEntriesTableFilterComposer
    extends Composer<_$SyncacheDriftDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get storedAt => $composableBuilder(
      column: $table.storedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ttlMs => $composableBuilder(
      column: $table.ttlMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get etag => $composableBuilder(
      column: $table.etag, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => ColumnFilters(column));
}

class $$CacheEntriesTableOrderingComposer
    extends Composer<_$SyncacheDriftDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get storedAt => $composableBuilder(
      column: $table.storedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ttlMs => $composableBuilder(
      column: $table.ttlMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get etag => $composableBuilder(
      column: $table.etag, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastModified => $composableBuilder(
      column: $table.lastModified,
      builder: (column) => ColumnOrderings(column));
}

class $$CacheEntriesTableAnnotationComposer
    extends Composer<_$SyncacheDriftDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get storedAt =>
      $composableBuilder(column: $table.storedAt, builder: (column) => column);

  GeneratedColumn<int> get ttlMs =>
      $composableBuilder(column: $table.ttlMs, builder: (column) => column);

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => column);
}

class $$CacheEntriesTableTableManager extends RootTableManager<
    _$SyncacheDriftDatabase,
    $CacheEntriesTable,
    CacheEntry,
    $$CacheEntriesTableFilterComposer,
    $$CacheEntriesTableOrderingComposer,
    $$CacheEntriesTableAnnotationComposer,
    $$CacheEntriesTableCreateCompanionBuilder,
    $$CacheEntriesTableUpdateCompanionBuilder,
    (
      CacheEntry,
      BaseReferences<_$SyncacheDriftDatabase, $CacheEntriesTable, CacheEntry>
    ),
    CacheEntry,
    PrefetchHooks Function()> {
  $$CacheEntriesTableTableManager(
      _$SyncacheDriftDatabase db, $CacheEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<int> storedAt = const Value.absent(),
            Value<int?> ttlMs = const Value.absent(),
            Value<String?> etag = const Value.absent(),
            Value<int?> lastModified = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CacheEntriesCompanion(
            key: key,
            value: value,
            version: version,
            storedAt: storedAt,
            ttlMs: ttlMs,
            etag: etag,
            lastModified: lastModified,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            required int version,
            required int storedAt,
            Value<int?> ttlMs = const Value.absent(),
            Value<String?> etag = const Value.absent(),
            Value<int?> lastModified = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CacheEntriesCompanion.insert(
            key: key,
            value: value,
            version: version,
            storedAt: storedAt,
            ttlMs: ttlMs,
            etag: etag,
            lastModified: lastModified,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CacheEntriesTable, CacheEntry>(table),
                    BaseReferences<_$SyncacheDriftDatabase, $CacheEntriesTable,
                        CacheEntry>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CacheEntriesTableProcessedTableManager = ProcessedTableManager<
    _$SyncacheDriftDatabase,
    $CacheEntriesTable,
    CacheEntry,
    $$CacheEntriesTableFilterComposer,
    $$CacheEntriesTableOrderingComposer,
    $$CacheEntriesTableAnnotationComposer,
    $$CacheEntriesTableCreateCompanionBuilder,
    $$CacheEntriesTableUpdateCompanionBuilder,
    (
      CacheEntry,
      BaseReferences<_$SyncacheDriftDatabase, $CacheEntriesTable, CacheEntry>
    ),
    CacheEntry,
    PrefetchHooks Function()>;
typedef $$CacheTagsTableCreateCompanionBuilder = CacheTagsCompanion Function({
  required String key,
  required String tag,
  Value<int> rowid,
});
typedef $$CacheTagsTableUpdateCompanionBuilder = CacheTagsCompanion Function({
  Value<String> key,
  Value<String> tag,
  Value<int> rowid,
});

class $$CacheTagsTableFilterComposer
    extends Composer<_$SyncacheDriftDatabase, $CacheTagsTable> {
  $$CacheTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tag => $composableBuilder(
      column: $table.tag, builder: (column) => ColumnFilters(column));
}

class $$CacheTagsTableOrderingComposer
    extends Composer<_$SyncacheDriftDatabase, $CacheTagsTable> {
  $$CacheTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tag => $composableBuilder(
      column: $table.tag, builder: (column) => ColumnOrderings(column));
}

class $$CacheTagsTableAnnotationComposer
    extends Composer<_$SyncacheDriftDatabase, $CacheTagsTable> {
  $$CacheTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get tag =>
      $composableBuilder(column: $table.tag, builder: (column) => column);
}

class $$CacheTagsTableTableManager extends RootTableManager<
    _$SyncacheDriftDatabase,
    $CacheTagsTable,
    CacheTag,
    $$CacheTagsTableFilterComposer,
    $$CacheTagsTableOrderingComposer,
    $$CacheTagsTableAnnotationComposer,
    $$CacheTagsTableCreateCompanionBuilder,
    $$CacheTagsTableUpdateCompanionBuilder,
    (
      CacheTag,
      BaseReferences<_$SyncacheDriftDatabase, $CacheTagsTable, CacheTag>
    ),
    CacheTag,
    PrefetchHooks Function()> {
  $$CacheTagsTableTableManager(
      _$SyncacheDriftDatabase db, $CacheTagsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> tag = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CacheTagsCompanion(
            key: key,
            tag: tag,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String tag,
            Value<int> rowid = const Value.absent(),
          }) =>
              CacheTagsCompanion.insert(
            key: key,
            tag: tag,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CacheTagsTable, CacheTag>(table),
                    BaseReferences<_$SyncacheDriftDatabase, $CacheTagsTable,
                        CacheTag>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CacheTagsTableProcessedTableManager = ProcessedTableManager<
    _$SyncacheDriftDatabase,
    $CacheTagsTable,
    CacheTag,
    $$CacheTagsTableFilterComposer,
    $$CacheTagsTableOrderingComposer,
    $$CacheTagsTableAnnotationComposer,
    $$CacheTagsTableCreateCompanionBuilder,
    $$CacheTagsTableUpdateCompanionBuilder,
    (
      CacheTag,
      BaseReferences<_$SyncacheDriftDatabase, $CacheTagsTable, CacheTag>
    ),
    CacheTag,
    PrefetchHooks Function()>;
typedef $$MutationOutboxEntriesTableCreateCompanionBuilder
    = MutationOutboxEntriesCompanion Function({
  required String id,
  required String key,
  required int seq,
  required String payload,
  required int queuedAt,
  Value<String?> optimisticSnapshot,
  Value<int> rowid,
});
typedef $$MutationOutboxEntriesTableUpdateCompanionBuilder
    = MutationOutboxEntriesCompanion Function({
  Value<String> id,
  Value<String> key,
  Value<int> seq,
  Value<String> payload,
  Value<int> queuedAt,
  Value<String?> optimisticSnapshot,
  Value<int> rowid,
});

class $$MutationOutboxEntriesTableFilterComposer
    extends Composer<_$SyncacheDriftDatabase, $MutationOutboxEntriesTable> {
  $$MutationOutboxEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get queuedAt => $composableBuilder(
      column: $table.queuedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get optimisticSnapshot => $composableBuilder(
      column: $table.optimisticSnapshot,
      builder: (column) => ColumnFilters(column));
}

class $$MutationOutboxEntriesTableOrderingComposer
    extends Composer<_$SyncacheDriftDatabase, $MutationOutboxEntriesTable> {
  $$MutationOutboxEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get queuedAt => $composableBuilder(
      column: $table.queuedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get optimisticSnapshot => $composableBuilder(
      column: $table.optimisticSnapshot,
      builder: (column) => ColumnOrderings(column));
}

class $$MutationOutboxEntriesTableAnnotationComposer
    extends Composer<_$SyncacheDriftDatabase, $MutationOutboxEntriesTable> {
  $$MutationOutboxEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get queuedAt =>
      $composableBuilder(column: $table.queuedAt, builder: (column) => column);

  GeneratedColumn<String> get optimisticSnapshot => $composableBuilder(
      column: $table.optimisticSnapshot, builder: (column) => column);
}

class $$MutationOutboxEntriesTableTableManager extends RootTableManager<
    _$SyncacheDriftDatabase,
    $MutationOutboxEntriesTable,
    MutationOutboxRecord,
    $$MutationOutboxEntriesTableFilterComposer,
    $$MutationOutboxEntriesTableOrderingComposer,
    $$MutationOutboxEntriesTableAnnotationComposer,
    $$MutationOutboxEntriesTableCreateCompanionBuilder,
    $$MutationOutboxEntriesTableUpdateCompanionBuilder,
    (
      MutationOutboxRecord,
      BaseReferences<_$SyncacheDriftDatabase, $MutationOutboxEntriesTable,
          MutationOutboxRecord>
    ),
    MutationOutboxRecord,
    PrefetchHooks Function()> {
  $$MutationOutboxEntriesTableTableManager(
      _$SyncacheDriftDatabase db, $MutationOutboxEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MutationOutboxEntriesTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$MutationOutboxEntriesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MutationOutboxEntriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> key = const Value.absent(),
            Value<int> seq = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<int> queuedAt = const Value.absent(),
            Value<String?> optimisticSnapshot = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MutationOutboxEntriesCompanion(
            id: id,
            key: key,
            seq: seq,
            payload: payload,
            queuedAt: queuedAt,
            optimisticSnapshot: optimisticSnapshot,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String key,
            required int seq,
            required String payload,
            required int queuedAt,
            Value<String?> optimisticSnapshot = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MutationOutboxEntriesCompanion.insert(
            id: id,
            key: key,
            seq: seq,
            payload: payload,
            queuedAt: queuedAt,
            optimisticSnapshot: optimisticSnapshot,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$MutationOutboxEntriesTable,
                        MutationOutboxRecord>(table),
                    BaseReferences<
                        _$SyncacheDriftDatabase,
                        $MutationOutboxEntriesTable,
                        MutationOutboxRecord>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MutationOutboxEntriesTableProcessedTableManager
    = ProcessedTableManager<
        _$SyncacheDriftDatabase,
        $MutationOutboxEntriesTable,
        MutationOutboxRecord,
        $$MutationOutboxEntriesTableFilterComposer,
        $$MutationOutboxEntriesTableOrderingComposer,
        $$MutationOutboxEntriesTableAnnotationComposer,
        $$MutationOutboxEntriesTableCreateCompanionBuilder,
        $$MutationOutboxEntriesTableUpdateCompanionBuilder,
        (
          MutationOutboxRecord,
          BaseReferences<_$SyncacheDriftDatabase, $MutationOutboxEntriesTable,
              MutationOutboxRecord>
        ),
        MutationOutboxRecord,
        PrefetchHooks Function()>;

class $SyncacheDriftDatabaseManager {
  final _$SyncacheDriftDatabase _db;
  $SyncacheDriftDatabaseManager(this._db);
  $$CacheEntriesTableTableManager get cacheEntries =>
      $$CacheEntriesTableTableManager(_db, _db.cacheEntries);
  $$CacheTagsTableTableManager get cacheTags =>
      $$CacheTagsTableTableManager(_db, _db.cacheTags);
  $$MutationOutboxEntriesTableTableManager get mutationOutboxEntries =>
      $$MutationOutboxEntriesTableTableManager(_db, _db.mutationOutboxEntries);
}
