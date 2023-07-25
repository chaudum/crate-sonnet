# crate-sonnet

A [jsonnet](https://jsonnet.org/) mixin library to create [CrateDB](https://crate.io) Kubernetes manifests.

---

## ⚠️ Warning

**This library is not meant for production usage yet!**

The APIs are still subject to change.

---

## 🏗️ Usage

This library is intended to be used with [Tanka](https://tanka.dev) to deploy Kubernetes manifests.

First, install the library using the [jsonnet-bundler](https://github.com/jsonnet-bundler/jsonnet-bundler):

```bash
jb install https://github.com/chaudum/crate-sonnet@main
```

To use this library in a Tanka environment import the `crate-sonnet/mai.libsonnet` like in the following, minimal example that generates manifests for a 3 node cluster with general purpose nodes.

```jsonnet
local crate = import 'crate-sonnet/main.libsonnet';

crate {
  _config+:: {
    namespace: 'my-cratedb-namespace',
    cluster: 'my-cratedb-cluster',

    general_purpose_replicas: 3,
    general_purpose_cpu: '1',
    general_purpose_memory: '1024Mi',
    general_purpose_heap: '512m',

    crate+: {
    },
  },
}
```

## ⚙️ Default configuration

```jsonnet
{
  _config+:: {
    create_namespace: true,

    // versions
    version: 'latest',
    jmx_exporter_version: '1.0.0',

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

    // flags
    enable_blobs: false,
    enable_rolling_upgrades: false,
    enable_master_data_deployment: false,
    enable_jmx_api: false,
  },
}
```
