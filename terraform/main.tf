provider "google" {
  version = "1.4.0"
  project = "${var.project}"
  region  = "${var.region}"
}

resource "google_compute_instance" "app" {
  name         = "reddit-app"
  machine_type = "g1-small"
  zone         = "${var.zone}"
  tags         = ["reddit-app"]

  # определение загрузочного диска
  boot_disk {
    initialize_params {
      image = "${var.disk_image}"
    }
  }

  # определение сетевого интерфейса
  network_interface {
    # сеть, к которой присоеденить данные интерфейс
    network = "default"

    # использовать ephemeral IP для доступа из Интернет
    access_config {}
  }

  metadata {
    sshKeys = "appuser:${file(var.public_key_path)}\nappuser1:${file("~/.ssh/appuser1.pub")}"
  }

  connection {
    type        = "ssh"
    user        = "appuser"
    agent       = false
    private_key = "${file(var.private_key_path)}"
  }

  provisioner "file" {
    source      = "files/puma.service"
    destination = "/tmp/puma.service"
  }

  provisioner "remote-exec" {
    script = "files/deploy.sh"
  }
}

resource "google_compute_instance" "app1" {
  name         = "reddit-app1"
  machine_type = "g1-small"
  zone         = "${var.zone}"
  tags         = ["reddit-app"]

  # определение загрузочного диска
  boot_disk {
    initialize_params {
      image = "${var.disk_image}"
    }
  }

  # определение сетевого интерфейса
  network_interface {
    # сеть, к которой присоеденить данные интерфейс
    network = "default"

    # использовать ephemeral IP для доступа из Интернет
    access_config {}
  }

  metadata {
    sshKeys = "appuser:${file(var.public_key_path)}\nappuser1:${file("~/.ssh/appuser1.pub")}"
  }

  connection {
    type        = "ssh"
    user        = "appuser"
    agent       = false
    private_key = "${file(var.private_key_path)}"
  }

  provisioner "file" {
    source      = "files/puma.service"
    destination = "/tmp/puma.service"
  }

  provisioner "remote-exec" {
    script = "files/deploy.sh"
  }
}

resource "google_compute_firewall" "firewall_puma" {
  name = "allow-puma-default"

  # Название сети, в которой действует правило
  network = "default"

  # Какой доступ разрешить
  allow {
    protocol = "tcp"
    ports    = ["9292"]
  }

  # Каким адресам разрешаем доступ
  source_ranges = ["0.0.0.0/0"]

  # Правило применимо для инстансов с тегом ...
  target_tags = ["reddit-app"]
}

resource "google_compute_instance_group" "reddit-app-instance-group" {
  name        = "reddit-app-instances"
  description = "reddit-apps"

  instances = [
    "${google_compute_instance.app.self_link}",
    "${google_compute_instance.app1.self_link}",
  ]

  named_port {
    name = "http"
    port = "9292"
  }

  zone = "${var.zone}"
}

resource "google_compute_global_forwarding_rule" "reddit-app-forwarding-rule" {
  name       = "reddit-app-forwarding-rule"
  target     = "${google_compute_target_http_proxy.reddit-app-http-proxy.self_link}"
  port_range = "80"
}

resource "google_compute_target_http_proxy" "reddit-app-http-proxy" {
  name        = "reddit-app-http-proxy"
  description = "reddit-app-proxy"
  url_map     = "${google_compute_url_map.reddit-app-url-map.self_link}"
}

resource "google_compute_url_map" "reddit-app-url-map" {
  name            = "reddit-app-url-map"
  description     = "reddit-app-url-map"
  default_service = "${google_compute_backend_service.reddit-app-backend-service.self_link}"

  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = "${google_compute_backend_service.reddit-app-backend-service.self_link}"

    path_rule {
      paths   = ["/*"]
      service = "${google_compute_backend_service.reddit-app-backend-service.self_link}"
    }
  }
}

resource "google_compute_backend_service" "reddit-app-backend-service" {
  name        = "reddit-app-backend-service"
  port_name   = "http"
  protocol    = "HTTP"
  timeout_sec = 10

  backend {
    group = "${google_compute_instance_group.reddit-app-instance-group.self_link}"
  }

  health_checks = ["${google_compute_http_health_check.reddit-app-health-check.self_link}"]
}

resource "google_compute_http_health_check" "reddit-app-health-check" {
  name               = "reddit-app-health-check"
  request_path       = "/"
  check_interval_sec = 1
  timeout_sec        = 1
  port		     = 9292 
}

