local k = import 'ksonnet-util/kausal.libsonnet';
local configMap = k.core.v1.configMap;
local deployment = k.apps.v1.deployment;

{
  _config+:: {
    create_namespace: true,

    // versions
    version: 'latest',
    jmx_exporter_version: '1.0.0',

    config_mount_name: 'crate',
    config_mount_path: '/crate/config',

    // general purpose node
    general_purpose_replicas: 3,
    general_purpose_cpu: '8',
    general_purpose_memory: '16Gi',
    general_purpose_heap: '8g',
    general_purpose_name: 'general-purpose',

    // master node
    master_replicas: 3,
    master_cpu: '1',
    master_memory: '1Gi',
    master_heap: '512m',
    master_name: 'master',

    // data node
    data_replicas: 5,
    data_cpu: '8',
    data_memory: '16Gi',
    data_heap: '8g',
    data_name: 'data',

    // disks
    data_disks: 1,
    data_pvc_size: '100Gi',
    data_pvc_storage_class: 'fast',
    data_pvc_mount_path: '/data',

    // ports
    http_listen_port: 4200,
    transport_listen_port: 4300,
    psql_listen_port: 5432,
    jmx_listen_port: 7979,
    jmx_exporter_listen_port: 8080,
    sql_exporter_listen_port: 8181,

    // flags
    enable_blobs: false,
    enable_rolling_upgrades: false,
    enable_master_data_deployment: false,
    enable_jmx_api: false,
    enable_sql_exporter: true,

    // crate.yml
    crate: {
      discovery: {
        seed_providers: 'srv',
        srv: {
          query:
            if $._config.enable_master_data_deployment then
              '_crate-transport._tcp.crate-%s.%s.svc.cluster.local.' % [$._config.master_name, $._config.namespace]
            else
              '_crate-transport._tcp.crate-%s.%s.svc.cluster.local.' % [$._config.general_purpose_name, $._config.namespace],
        },
      },
      processors: std.parseInt($._config.general_purpose_cpu),
      bootstrap: {
        memory_lock: true,
      },
      network: {
        host: '_local_,_site_',
      },
      http: {
        port: $._config.http_listen_port,
      },
      transport: {
        tcp: {
          port: $._config.transport_listen_port,
        },
      },
      psql: {
        port: $._config.psql_listen_port,
      },
      cluster: {
        name: $._config.cluster,
        initial_master_nodes:
          if $._config.enable_master_data_deployment then
            std.join(',', [
              'crate-%s-%s' % [$._config.master_name, i]
              for i in std.range(0, $._config.master_replicas - 1)
            ])
          else
            std.join(',', [
              'crate-%s-%s' % [$._config.general_purpose_name, i]
              for i in std.range(0, $._config.general_purpose_replicas - 1)
            ]),
      },
      gateway:
        if $._config.enable_master_data_deployment then
          {
            expected_data_nodes: $._config.data_replicas,
            recover_after_data_nodes: std.ceil($._config.data_replicas / 2),
          }
        else
          {
            expected_data_nodes: $._config.general_purpose_replicas,
            recover_after_data_nodes: std.ceil($._config.general_purpose_replicas / 2),
          },
      path: {
        logs: '/dev/null',
        data: std.join(',', [
          '%s/disk-%s/data' % [$._config.data_pvc_mount_path, i]
          for i in std.range(1, $._config.data_disks)
        ]),
      },
      blobs: if $._config.enable_blobs then {
        path: std.join(',', [
          '%s/disk-%s/blob' % [$._config.data_pvc_mount_path, i]
          for i in std.range(1, $._config.data_disks)
        ]),
      } else {},
    },
    log4j_plain:
      |||
        # Crate uses log4j as internal logging abstraction.
        # Configure log4j as you need it to behave by setting the log4j prefixes in
        # this file.
        status = error

        rootLogger.level = debug
        rootLogger.appenderRefs = stdout, stderr
        rootLogger.appenderRef.stdout.ref = STDOUT
        rootLogger.appenderRef.stderr.ref = STDERR


        # log action execution errors for easier debugging
        # logger.action.name = org.crate.action.sql
        # logger.action.level = debug

        #  Peer shard recovery
        # logger.indices_recovery.name: indices.recovery
        # logger.indices_recovery.level: DEBUG

        #  Discovery
        #  Crate will discover the other nodes within its own cluster.
        #  If you want to log the discovery process, set the following:
        # logger.discovery.name: discovery
        # logger.discovery.level: TRACE

        # mute amazon s3 client logging a bit
        logger.aws.name = com.amazonaws
        logger.aws.level = warn

        # Define your appenders here.
        # Like mentioned above, use the log4j prefixes to configure for example the
        # type or layout.
        # For all available settings, take a look at the log4j documentation.
        # http://logging.apache.org/log4j/2.x/
        # http://logging.apache.org/log4j/2.x/manual/appenders.html

        # configure stdout
        appender.consoleOut.type = Console
        appender.consoleOut.name = STDOUT
        appender.consoleOut.target = System.out
        appender.consoleOut.direct = true
        appender.consoleOut.layout.type = PatternLayout
        appender.consoleOut.layout.pattern = [%d{ISO8601}][%-5p][%-25c{1.}] [%node_name] %marker%m%n
        appender.consoleOut.filter.threshold.type = ThresholdFilter
        appender.consoleOut.filter.threshold.level = warn
        appender.consoleOut.filter.threshold.onMatch = DENY
        appender.consoleOut.filter.threshold.onMismatch = ACCEPT

        # configure stderr
        appender.consoleErr.type = Console
        appender.consoleErr.name = STDERR
        appender.consoleErr.target = SYSTEM_ERR
        appender.consoleErr.direct = true
        appender.consoleErr.layout.type = PatternLayout
        appender.consoleErr.layout.pattern = [%d{ISO8601}][%-5p][%-25c{1.}] [%node_name] %marker%m%n
        appender.consoleErr.filter.threshold.type = ThresholdFilter
        appender.consoleErr.filter.threshold.level = warn
        appender.consoleErr.filter.threshold.onMatch = ACCEPT
        appender.consoleErr.filter.threshold.onMismatch = DENY
      |||
    ,
    // TODO(chaudum): Make encoding as properties file work
    log4j: {
      newConsoleAppender(name, target):: {
        type: 'Console',
        name: name,
        target: target,
        layout: {
          type: 'PatternLayout',
          pattern: '[%d{ISO8601}][%-5p][%-25c{1.}] [%node_name] %marker%m%n',
        },
        filter: {
          threshold: {
            type: 'ThresholdFilter',
            level: 'warn',
            onMatch: 'DENY',
            onMismatch: 'ACCEPT',
          },
        },
      },
      status: 'error',
      rootLogger: {
        level: 'info',
        appenderRefs: 'stdout, stderr',
        appenderRef: {
          stdout: 'STDOUT',
          stderr: 'STDERR',
        },
      },
      appender: {
        consoleOut: $._config.log4j.newConsoleAppender('STDOUT', 'System.out') {
          filter+: {
            threshold+: {
              onMatch: 'DENY',
              onMismatch: 'ACCEPT',
            },
          },
        },
        consoleErr: $._config.log4j.newConsoleAppender('STDERR', 'SYSTEM_ERR') {
          filter+: {
            threshold+: {
              onMatch: 'ACCEPT',
              onMismatch: 'DENY',
            },
          },
        },
      },
    },
  },

  config_file:
    configMap.new($._config.config_mount_name) +
    configMap.withData({
      'crate.yml': k.util.manifestYaml($._config.crate),
      // 'log4j2.properties': $.util.toProperties($._config.log4j),
      'log4j2.properties': $._config.log4j_plain,
    }),

  config_hash_mixin::
    deployment.mixin.spec.template.metadata.withAnnotationsMixin({
      config_hash: std.md5(std.toString($._config.crate + $._config.log4j_plain)),
    }),
}
