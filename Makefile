#!/usr/bin/env -S make -f

.SUFFIXES:
.PHONY := registry-push registry-run podman-run clean clean-data
.DEFAULT_GOAL := podman-run

GROCY_VERSION	?= 4.5.0
BASE_IMAGE		?= docker.io/php:8.3-fpm-alpine

#GROCY_VERSION	?= $(shell gh api repos/grocy/grocy/releases --paginate --jq 'map(select(.draft==false and .prerelease==false and (.tag_name | startswith("v"))).tag_name[1:])|max')

SHELL           := /bin/bash
REGISTRY        ?= localhost:5000
IMAGE    		?= grocy
NAME			= $(REGISTRY)/$(IMAGE):$(GROCY_VERSION)
PLATFORM		?= linux/amd64,linux/arm64/v8
PUSH			:= true

DATADIR			= ./data
BUILDDIR		= ./build
SRCDIR			= ./src

$(DATADIR) $(BUILDDIR):
	mkdir -p $@

$(BUILDDIR)/metadata-$(GROCY_VERSION).json: Dockerfile src/* |$(BUILDDIR)
	buildctl build --frontend gateway.v0 --opt source=docker.io/docker/dockerfile:1 --local context=. --local dockerfile=. \
	--output type=image,name=$(NAME)$(SUFFIX),push=$(PUSH) \
	--opt build-arg:GROCY_VERSION=$(GROCY_VERSION) \
	--opt build-arg:BASE_IMAGE=$(BASE_IMAGE) \
	--opt platform=$(PLATFORM) \
	--opt attest:sbom= \
	--opt attest:provenance=mode=max \
	--metadata-file $@ \
	$(OPTS)

$(BUILDDIR)/oci-$(GROCY_VERSION).tar: Dockerfile src/* |$(BUILDDIR)
	buildctl build --frontend gateway.v0 --opt source=docker.io/docker/dockerfile:1 --local context=. --local dockerfile=. \
	--output type=oci,dest=$@,name=$(NAME)$(SUFFIX) \
	--opt build-arg:GROCY_VERSION=$(GROCY_VERSION) \
	--opt build-arg:BASE_IMAGE=$(BASE_IMAGE) \
	$(OPTS)

registry-push: $(BUILDDIR)/metadata-$(GROCY_VERSION).json;
registry-run: $(BUILDDIR)/metadata-$(GROCY_VERSION).json |$(DATADIR)
	podman run --name=grocy --rm --replace --publish=127.0.0.1:8080:8080 --read-only --volume=$(DATADIR):/data -e GROCY_CURRENCY=EUR -ti "$(shell jq --raw-output '"\(.["image.name"])@\(.["containerimage.digest"])"' $<)"

podman-run: $(BUILDDIR)/oci-$(GROCY_VERSION).tar |$(DATADIR)
	podman run --name=grocy --rm --replace --publish=127.0.0.1:8080:8080 --read-only --volume=$(DATADIR):/data -e GROCY_CURRENCY=EUR -ti oci-archive:$<

podman-run-demo: $(BUILDDIR)/oci-$(GROCY_VERSION).tar
	podman run --name=grocy-demo --rm --replace --publish=127.0.0.1:8080:8080 --read-only -e GROCY_MODE=demo -e GROCY_CURRENCY=EUR -ti oci-archive:$<

clean:
	rm -rf $(BUILDDIR)

clean-data:
	podman unshare rm -rf $(DATADIR)