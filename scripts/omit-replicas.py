"""Let HPA own Deployment replicas while keeping local overlay previews readable."""
import sys
import yaml
for document in yaml.safe_load_all(sys.stdin):
    if document and document.get("kind") == "Deployment":
        document["spec"].pop("replicas", None)
    if document:
        print(yaml.safe_dump(document, sort_keys=False), end="---\n")
