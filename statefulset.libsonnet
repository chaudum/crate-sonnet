local k = import 'ksonnet-util/kausal.libsonnet';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,
  local pvc = k.core.v1.persistentVolumeClaim,
  local envVar = k.core.v1.envVar,

  newCrateContainer(args, cpu, mem, heap, dataVolumeMounts=[], containerName='crate')::
    local flags =
      k.util.mapToFlags($.common_args + args, prefix='-C') +
      if $._config.enable_jmx_api then
        k.util.mapToFlags($.jmx_args, prefix='-D')
      else
        [];

    container.new(containerName, $._images.crate) +
    container.withPorts($.util.defaultPorts + $.util.extraPorts) +
    container.withArgsMixin(flags) +
    container.withVolumeMountsMixin(dataVolumeMounts) +
    container.withEnvMixin([
      envVar.new('CRATE_HEAP_SIZE', heap),
      envVar.new('CRATE_JAVA_OPTS', '-javaagent:/crate/ext/crate-jmx-exporter-%s.jar=%s' % [
        $._config.jmx_exporter_version,
        $._config.jmx_exporter_listen_port,
      ]),
      envVar.new('POD_NAME', '') + envVar.valueFrom.fieldRef.withFieldPath('metadata.name'),
      envVar.new('POD_NAMESPACE', '') + envVar.valueFrom.fieldRef.withFieldPath('metadata.namespace'),
    ]) +
    $.util.readinessProbe +
    k.util.resourcesRequests(cpu, mem) +
    k.util.resourcesLimits(null, mem) +
    {},

  newCrateStatefulSet(container, name='node', replicas=3, pvcs=[], prefix='crate')::
    local fqn = '%s-%s' % [prefix, name];
    statefulSet.new(fqn, replicas, [container], pvcs) +
    statefulSet.mixin.spec.withServiceName(fqn) +
    statefulSet.mixin.spec.withPodManagementPolicy('Parallel') +
    statefulSet.mixin.spec.updateStrategy.withType(if $._config.enable_rolling_upgrades then 'RollingUpdate' else 'OnDelete') +
    statefulSet.mixin.spec.template.spec.withInitContainers([$.sysctl_container, $.jmx_download_container]) +
    statefulSet.mixin.spec.template.spec.securityContext.withFsGroup(1000) +
    statefulSet.mixin.spec.template.spec.withTerminationGracePeriodSeconds(600) +
    k.util.configVolumeMount($._config.config_mount_name, $._config.config_mount_path) +
    k.util.emptyVolumeMount('ext', '/crate/ext') +
    k.util.antiAffinity +
    $.config_hash_mixin +
    {},

  crate_ext_volume_mount::
    [volumeMount.new('ext', '/crate/ext')],

  jmx_args:: {
    'com.sun.management.jmxremote': '',
    'com.sun.management.jmxremote.port': $._config.jmx_listen_port,
    'com.sun.management.jmxremote.ssl': false,
    'com.sun.management.jmxremote.authenticate': false,
    'com.sun.management.jmxremote.rmi.port': $._config.jmx_listen_port,
    'java.rmi.server.hostname': '${POD_NAME}',
  },

  common_args:: {
    'path.conf': $._config.config_mount_path,
    'node.name': '${POD_NAME}',
    'node.attr.namespace': '${POD_NAMESPACE}',
  },

  sysctl_container::
    container.new('sysctl', $._images.busybox) +
    container.withCommandMixin(['sysctl']) +
    container.withArgsMixin([
      '-w',
      'vm.max_map_count=262144',
    ]) +
    container.securityContext.withPrivileged(true) +
    container.withVolumeMountsMixin($.crate_ext_volume_mount) +
    {},

  jmx_download_container::
    container.new('download', $._images.crate) +
    container.withCommandMixin(['curl']) +
    container.withArgsMixin([
      '-sLo',
      '/crate/ext/crate-jmx-exporter-%(jmx_exporter_version)s.jar' % $._config,
      'https://repo1.maven.org/maven2/io/crate/crate-jmx-exporter/%(jmx_exporter_version)s/crate-jmx-exporter-%(jmx_exporter_version)s.jar' % $._config,
    ]) +
    container.withVolumeMountsMixin($.crate_ext_volume_mount) +
    {},

  // General purpose nodes

  general_purpose_args:: {
    'node.master': 'true',
    'node.data': 'true',
    'node.attr.type': 'general-purpose',
  },

  general_purpose_container::
    $.newCrateContainer(
      $.general_purpose_args,
      $._config.general_purpose_cpu,
      $._config.general_purpose_memory,
      $._config.general_purpose_heap,
      $.data_volume_mount
    ) +
    {},

  general_purpose_statefulset:
    if !$._config.enable_master_data_deployment then
      $.newCrateStatefulSet(
        $.general_purpose_container,
        $._config.general_purpose_name,
        $._config.general_purpose_replicas,
        $.data_pvc,
      ) +
      {}
    else {},

  general_purpose_service:
    if !$._config.enable_master_data_deployment then
      k.util.serviceFor($.general_purpose_statefulset)
    else {},

  // Master nodes

  master_args:: {
    'node.master': 'true',
    'node.data': 'false',
    'node.attr.type': 'master',
  },

  master_container::
    $.newCrateContainer(
      $.master_args,
      $._config.master_cpu,
      $._config.master_memory,
      $._config.master_heap
    ) +
    {},

  master_statefulset:
    if $._config.enable_master_data_deployment then
      $.newCrateStatefulSet(
        $.master_container,
        $._config.master_name,
        $._config.master_replicas,
      ) +
      statefulSet.mixin.spec.updateStrategy.withType('RollingUpdate') +
      {}
    else {},

  master_service:
    if $._config.enable_master_data_deployment then
      k.util.serviceFor($.master_statefulset)
    else {},

  // Data nodes

  data_args:: {
    'node.master': 'false',
    'node.data': 'true',
    'node.attr.type': 'data',
  },

  data_container::
    $.newCrateContainer(
      $.data_args,
      $._config.data_cpu,
      $._config.data_memory,
      $._config.data_heap,
      $.data_volume_mount
    ) +
    {},

  data_statefulset:
    if $._config.enable_master_data_deployment then
      $.newCrateStatefulSet(
        $.data_container,
        $._config.data_name,
        $._config.data_replicas,
        $.data_pvc,
      ) +
      {}
    else {},

  data_service:
    if $._config.enable_master_data_deployment then
      k.util.serviceFor($.data_statefulset)
    else {},

}
