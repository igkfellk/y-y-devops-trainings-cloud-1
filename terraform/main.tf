terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  service_account_key_file = "./tf_key.json"
  folder_id                = local.folder_id 
  zone                     = "ru-central1-a"
}

resource "yandex_vpc_network" "foo" {}

resource "yandex_vpc_subnet" "foo" {
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.foo.id
  v4_cidr_blocks = ["10.10.0.0/24"]
}

resource "yandex_container_registry" "ikfellk-registry" {
  name = "ikfellk-registry"
}

locals {
  folder_id = "<INSERT YOUR FOLDER ID>"
  service-accounts = toset([
    "test-1",
    "test-2",
  ])
  test-1-roles = toset([
    "container-registry.images.puller",
    "monitoring.editor",
  ])
  test-2-roles = toset([
    "compute.editor",
    "iam.serviceAccounts.user",
    "load-balancer.admin",
    "vpc.publicAdmin",
    "vpc.user",
  ])
}
resource "yandex_iam_service_account" "service-accounts" {
  for_each = local.service-accounts
  name     = "${local.folder_id}-${each.key}"
}
resource "yandex_resourcemanager_folder_iam_member" "test-1-roles" {
  for_each  = local.test-1-roles
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["test-1"].id}"
  role      = each.key
}
resource "yandex_resourcemanager_folder_iam_member" "test-2-roles" {
  for_each  = local.test-2-roles
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["test-2"].id}"
  role      = each.key
}

data "yandex_compute_image" "coi" {
  family = "container-optimized-image"
}

resource "yandex_compute_instance_group" "catgpt" {
  depends_on = [
    yandex_resourcemanager_folder_iam_member.test-2-roles
  ]
  name               = "catgpt"
  service_account_id = yandex_iam_service_account.service-accounts["test-2"].id
  allocation_policy {
    zones = ["ru-central1-a"]
  }
  deploy_policy {
    max_unavailable = 1
    max_creating    = 2
    max_expansion   = 2
    max_deleting    = 2
  }
  scale_policy {
    fixed_scale {
      size = 2
    }
  }
  instance_template {
    platform_id        = "standard-v2"
    service_account_id = yandex_iam_service_account.service-accounts["test-1"].id
    resources {
      cores         = 2
      memory        = 1
      core_fraction = 5
    }
    scheduling_policy {
      preemptible = true
    }
    network_interface {
      network_id = yandex_vpc_network.foo.id
      subnet_ids = ["${yandex_vpc_subnet.foo.id}"]
      nat        = true
    }
    boot_disk {
      initialize_params {
        type     = "network-hdd"
        size     = "30"
        image_id = data.yandex_compute_image.coi.id
      }
    }
    metadata = {
      docker-compose = templatefile(
        "${path.module}/docker-compose.yaml",
        {
          folder_id   = "${local.folder_id}",
          registry_id = "${yandex_container_registry.ikfellk-registry.id}",
        }
      )
      user-data = file("${path.module}/cloud-config.yaml")
      ssh-keys  = "ubuntu:${file("~/.ssh/devops_training.pub")}"
    }
  }
  load_balancer {
    target_group_name = "catgpt"
  }
}

resource "yandex_lb_network_load_balancer" "lb-catgpt" {
  name = "catgpt"

  listener {
    name        = "cat-listener"
    port        = 80
    target_port = 8080
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_compute_instance_group.catgpt.load_balancer[0].target_group_id

    healthcheck {
      name = "http"
      http_options {
        port = 8080
        path = "/ping"
      }
    }
  }
}
