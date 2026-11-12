# Lab 07 - Deploying a Microservices Application on Amazon EKS

Lab instructions: https://norbutlepcha25.github.io/dso303/Lab/Lab-07-EKS.html

- Report: [Report.md](Report.md)
- Independent exercises: [exercises.md](exercises.md)
- Notes and review questions: [../../notes/lab-07-notes.md](../../notes/lab-07-notes.md)
- Manifests: [../../manifests/lab-07/](../../manifests/lab-07/)
- Verify: `./scripts/utilities/verify-lab-07.sh`
- Support probe: `./scripts/utilities/eks-support-probe.sh`

Run `export AWS_DEFAULT_REGION=us-east-1` first in a new terminal, because the `floci` profile's region is `ap-south-1`. The kubectl context is `usms-eks` (API on `https://localhost:6501`), with `usms` as its default namespace.

Do not run `scripts/cleanup/lab-07-cleanup.sh` until the end of the course.
