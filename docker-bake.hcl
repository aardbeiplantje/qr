group "default" {
  targets = ["_local"]
}
group "local" {
  targets = ["_local"]
}
group "release" {
  targets = ["qrencode"]
}
variable "DOCKER_REGISTRY" {
  default = "ghcr.io"
}
variable "DOCKER_REPOSITORY" {
  default = "registry"
}
variable "DOCKER_TAG" {
  default = "latest"
}
variable "DOCKER_IMAGE_NAME" {
  default = "qrencode"
}
variable "DOCKER_REPOSITORY_LOCAL" {
  default = "qrencode"
}

target "_common" {
  context = "."
  dockerfile = "Dockerfile"
  platforms = ["linux/amd64"]
  networks = ["host"]
  buildkit = true
}

target "_local" {
  inherits = ["_common"]
  target = "runtime"
  tags = [
    "local/${DOCKER_REPOSITORY_LOCAL}/${DOCKER_IMAGE_NAME}:${DOCKER_TAG}",
  ]
  output = [
    "type=docker,name=local/${DOCKER_REPOSITORY_LOCAL}/${DOCKER_IMAGE_NAME}:${DOCKER_TAG}"
  ]
}

target "qrencode" {
  pull = true
  name = "qrencode-${env}"
  matrix = {
    env = ["release"]
  }
  progress = ["plain", "tty"]
  tags = [
    "${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/qrencode:${DOCKER_TAG}",
  ]
  output = [
    "type=image,name=${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/qrencode:${DOCKER_TAG},push=true"
  ]
  cache-to = [
    "type=registry,ref=${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/qrencode:cache,mode=max"
  ]
  cache-from = [
    "type=registry,ref=${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/qrencode:cache",
    "type=registry,ref=${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/qrencode:${DOCKER_TAG}"
  ]
  target = "runtime"
  buildkit = true
  attest = [
    "type=provenance,mode=max",
    "type=sbom",
  ]
  context = "."
  dockerfile = "Dockerfile"
  networks = ["host"]
  platforms = [
    "linux/arm/v6",
    "linux/amd64"
  ]
}
