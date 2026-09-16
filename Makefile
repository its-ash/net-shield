.PHONY: run build deploy

run:
	flutter run

build:
	flutter build apk --release

deploy: build
	git checkout main
	git add -A
	git commit -m "$$(copilot -sp 'Analyze the staged git changes and generate a concise commit message. Output ONLY the commit message. Do not execute any commands. Do not include quotes, markdown, explanation, or bullet points.')"
	@version=$$(grep '^version:' pubspec.yaml | head -1 | awk '{print $$2}' | cut -d '+' -f 1) && \
	build_no=$$(grep '^version:' pubspec.yaml | head -1 | awk '{print $$2}' | cut -d '+' -f 2) && \
	if gh release view "v$$version" >/dev/null 2>&1; then \
		major=$$(echo "$$version" | cut -d. -f1) && \
		minor=$$(echo "$$version" | cut -d. -f2) && \
		patch=$$(echo "$$version" | cut -d. -f3) && \
		patch=$$((patch + 1)) && \
		version="$$major.$$minor.$$patch" && \
		build_no=$$((build_no + 1)) && \
		sed -i '' "s/^version: .*/version: $$version+$$build_no/" pubspec.yaml && \
		git add pubspec.yaml && \
		git commit -m "chore: bump version to $$version" ; \
	fi && \
	echo "Creating GitHub release v$$version…" && \
	gh release create "v$$version" \
		build/app/outputs/flutter-apk/app-release.apk \
		--title "v$$version" \
		--generate-notes
	git push origin main && git push --tags