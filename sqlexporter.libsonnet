local k = import 'ksonnet-util/kausal.libsonnet';

{
  local configMap = k.core.v1.configMap,
  local container = k.core.v1.container,
  local volumeMount = k.core.v1.volumeMount,

  // TODO(chaudum): Should these be exposed in $._config object?
  local mount_name = 'sql-exporter',
  local mount_path = '/sql-exporter/config',

  _config+:: {
    sql_exporter: {
      global: {
        // Subtracted from Prometheus' scrape_timeout to give us some headroom and prevent Prometheus from
        // timing out first.
        scrape_timeout_offset: '500ms',
        // Minimum interval between collector runs: by default (0s) collectors are executed on every scrape.
        min_interval: '1s',
        // Maximum number of open connections to any one target. Metric queries will run concurrently on
        // multiple connections.
        max_connections: 10,
        // Maximum number of idle connections to any one target.
        max_idle_connections: 3,
      },
      target: {
        data_source_name: 'postgres://%s@localhost:%s?sslmode=disable' % ['crate', $._config.psql_listen_port],
        collectors: [c.collector_name for c in $._config.sql_exporter_collectors],
      },
      collector_files: [
        '*.collector.yml',
      ],
    },
    sql_exporter_collectors: [
      {
        collector_name: 'default',
        metrics: [
          {
            metric_name: 'crate_table_health',
            type: 'gauge',
            help: 'Table health (1=GREEN, 2=YELLOW, 3=RED)',
            key_labels: ['schema', 'table'],
            static_labels: {},
            values: ['severity'],
            query: |||
              SELECT table_schema AS "schema", table_name AS "table", severity
              FROM sys.health
            |||,
          },
          {
            metric_name: 'crate_table_shards_total',
            type: 'gauge',
            help: 'Underreplicated shards per table',
            key_labels: ['schema', 'table'],
            value_label: 'state',
            static_labels: {},
            values: ['underreplicated', 'missing'],
            query: |||
              SELECT table_schema AS "schema", table_name AS "table", missing_shards AS "missing", underreplicated_shards AS "underreplicated"
              FROM sys.health
            |||,
          },
          {
            metric_name: 'crate_shards_total',
            type: 'gauge',
            help: 'Shard count by table and state',
            key_labels: ['schema', 'table', 'state', 'primary'],
            static_labels: {},
            values: ['value'],
            query: |||
              SELECT COUNT(*) AS "value", schema_name AS "schema", table_name AS "table", LOWER(state) AS "state", "primary"
              FROM sys.shards
              GROUP BY "schema", "table", "state", "primary"
            |||,
          },
        ],
      },
    ],
  },

  sql_exporter_args:: {
    'config.file': '%s/config.yml' % mount_path,
    'web.listen-address': ':%s' % $._config.sql_exporter_listen_port,
    'web.metrics-path': '/metrics',
  },

  sql_exporter_container::
    container.new(mount_name, $._images.sql_exporter) +
    container.withArgsMixin(k.util.mapToFlags($.sql_exporter_args)) +
    container.withVolumeMountsMixin([
      volumeMount.new(mount_name, mount_path),
    ]) +
    k.util.resourcesRequests('500m', '128Mi') +
    k.util.resourcesLimits('1000m', '256Mi') +
    {},

  sql_exporter_config_file:
    configMap.new(mount_name) +
    configMap.withData(
      { 'config.yml': k.util.manifestYaml($._config.sql_exporter) }
      + { ['%s.collector.yml' % collector.collector_name]: k.util.manifestYaml(collector) for collector in $._config.sql_exporter_collectors }
    ),

}
