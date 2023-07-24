local k = import 'ksonnet-util/kausal.libsonnet';

{
  local containerPort = k.core.v1.containerPort,
  local container = k.core.v1.container,

  util+:: {
    defaultPorts:: [
      containerPort.new(name='http', port=$._config.http_listen_port),
      containerPort.new(name='transport', port=$._config.transport_listen_port),
      containerPort.new(name='psql', port=$._config.psql_listen_port),
    ],

    extraPorts:: [
      containerPort.new(name='jmx', port=$._config.jmx_listen_port),
      containerPort.new(name='jmx-exporter', port=$._config.jmx_exporter_listen_port),
    ],

    readinessProbe::
      container.mixin.readinessProbe.httpGet.withPath('/ready') +
      container.mixin.readinessProbe.httpGet.withPort($._config.jmx_exporter_listen_port) +
      container.mixin.readinessProbe.withInitialDelaySeconds(15) +
      container.mixin.readinessProbe.withTimeoutSeconds(1),

    toProperties(obj)::
      local delim = '.';
      local convert(k, v, prefix='') =
        if std.isObject(v) then
          std.join(
            '\n',
            [
              convert(x, v[x], prefix + k + delim)
              for x in std.objectFields(v)
            ]
          )
        else
          '%s%s = %s' % [prefix, k, v]
      ;

      if !std.isObject(obj) then
        error 'must be object'
      else
        std.join(
          '\n',
          [
            convert(k, obj[k], '')
            for k in std.objectFields(obj)
          ]
        ),

  },

  namespace: if $._config.create_namespace then
    k.core.v1.namespace.new($._config.namespace)
  else {},
}
