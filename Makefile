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
	echo "Creating GitHub release v$$version…" && \
	gh release create "v$$version" \
		build/app/outputs/flutter-apk/app-release.apk \
		--title "v$$version" \
		--generate-notes
	git push origin main