HUGO := hugo
HUGO_VERSION := 0.53
HTMLPROOFER_VERSION := 3.10.2
NPM := npm
GCLOUD := gcloud
GCP_PROJECT := gvisor-website

# Source Go files. example: main.go foo/bar.go
GO_SOURCE = $(shell find cmd/gvisor-website -type f -name "*.go" | sed 's/ /\\ /g')
# Target Go files. example: public/main.go public/foo/bar.go
GO_TARGET = $(shell cd cmd/gvisor-website && find . -type f -name "*.go" | sed 's/ /\\ /g' | sed 's/^.\//public\//')

default: website
.PHONY: default

website: all-upstream public/app.yaml $(GO_TARGET) public/static
.PHONY: website

public:
	mkdir -p public
public/app.yaml: public
	cp -vr cmd/gvisor-website/app.yaml public/



# Load repositories.
upstream:
	mkdir -p upstream
upstream-%: upstream
	if [ -d upstream/$* ]; then (cd upstream/$* && git pull --rebase); else git clone https://gvisor.googlesource.com/$*/ upstream/$*; fi
all-upstream: upstream-gvisor upstream-community
# All repositories are listed here: force updates.
.PHONY: all-upstream upstream-%

# This target regenerates the sigs directory; this is not PHONY.
content/docs/community/sigs: upstream/community $(wildcard upstream/community/sigs/*)
	rm -rf content/docs/community/sigs && mkdir -p content/docs/community/sigs
	for file in $(shell cd upstream/community/sigs && ls -1 *.md | cut -d'.' -f1 | grep -v TEMPLATE); do      \
		title=$$(cat upstream/community/sigs/$$file.md | grep -E '^# ' | cut -d' ' -f2-);                 \
		echo -e "+++\ntitle = \"$$title\"\n+++\n" > content/docs/community/sigs/$$file.md;                  \
		cat upstream/community/sigs/$$file.md |grep -v -E '^# ' >> content/docs/community/sigs/$$file.md; \
	done

$(GO_TARGET): public $(GO_SOURCE)
	cd cmd/gvisor-website && find . -name "*.go" -exec cp --parents \{\} ../../public \;

deploy: public/app.yaml
	cd public && $(GCLOUD) app deploy
.PHONY: deploy

public/static: node_modules config.toml $(shell find archetypes assets content themes -type f | sed 's/ /\\ /g')
	$(HUGO)

server: all-upstream
	$(HUGO) server -FD --port 8080

node_modules: package.json package-lock.json
	# Use npm ci because npm install will update the package-lock.json.
	# See: https://github.com/npm/npm/issues/18286
	$(NPM) ci

cloud-build:
	gcloud builds submit --config cloudbuild/cloudbuild.yaml .

hugo-docker-image:
	docker build --build-arg HUGO_VERSION=$(HUGO_VERSION) -t gcr.io/gvisor-website/hugo:$(HUGO_VERSION) cloudbuild/hugo/
	docker push gcr.io/gvisor-website/hugo:$(HUGO_VERSION)
.PHONY: hugo-docker-image

htmlproofer-docker-image:
	docker build --build-arg HTMLPROOFER_VERSION=$(HTMLPROOFER_VERSION) -t gcr.io/gvisor-website/html-proofer:$(HTMLPROOFER_VERSION) cloudbuild/html-proofer/
	docker push gcr.io/gvisor-website/html-proofer:$(HTMLPROOFER_VERSION)
.PHONY: htmlproofer-docker-image

clean:
	rm -rf public/ resources/ node_modules/ upstream/
.PHONY: clean
