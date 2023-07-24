local k = import 'ksonnet-util/kausal.libsonnet';
local volumeMount = k.core.v1.volumeMount;
local pvc = k.core.v1.persistentVolumeClaim;

{
  local data_disk_name = 'data',

  data_pvc:: [
    pvc.new('%s-%s' % [data_disk_name, i]) +
    pvc.mixin.spec.resources.withRequests({ storage: $._config.data_pvc_size }) +
    pvc.mixin.spec.withAccessModes(['ReadWriteOnce']) +
    pvc.mixin.spec.withStorageClassName($._config.data_pvc_storage_class)
    for i in std.range(1, $._config.data_disks)
  ],

  data_volume_mount:: [
    volumeMount.new('%s-%s' % [data_disk_name, i], '%s/disk-%s' % [$._config.data_pvc_mount_path, i])
    for i in std.range(1, $._config.data_disks)
  ],

}
