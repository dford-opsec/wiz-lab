Wiz Technical Exercise v4 - Cloud Security Demo Environment

Overview

This repository contains the Infrastructure as Code (IaC), Kubernetes manifests, and CI/CD pipelines used to deploy a containerized two-tier web application (Tasky) on Google Cloud Platform (GCP).

This environment was purpose-built for the Wiz Technical Exercise. It follows modern DevOps principles but has been engineered with intentional configuration weaknesses and vulnerabilities to simulate real-world threat vectors and demonstrate cloud native security tooling.

Architecture

The environment consists of a public-facing GCP Cloud Load Balancer routing traffic to a Go-based web application running on a private Google Kubernetes Engine (GKE) cluster. The application connects to a MongoDB database hosted on a standalone Compute Engine VM in a public subnet.

![Architecture Diagram](./diagram.svg)



Intentional Security Misconfigurations

To fulfill the requirements of the technical exercise, the following vulnerabilities have been purposefully injected into the environment:

Exposed Infrastructure: Port 22 (SSH) on the MongoDB Compute Engine VM is exposed to the public internet (0.0.0.0/0).

Outdated Software: The database VM runs a 1+ year outdated version of Linux and MongoDB (v4.4).

Data Exposure: The Cloud Storage bucket containing automated daily database backups is configured for public read and listing (allUsers).

Overly Permissive Identities: * The MongoDB VM is granted overly permissive CSP permissions (Editor/Compute Admin).

The containerized web application in GKE is assigned a cluster-wide Kubernetes admin role.

CI/CD Pipelines (DevSecOps)

This repository utilizes GitHub Actions to automate the deployment process, divided into two distinct pipelines:

IaC Deployment (terraform.yml): Automatically provisions the foundational GCP infrastructure (VPC, Subnets, GKE Cluster, Compute Engine VM, Storage Bucket, and Firewall rules). Includes IaC security scanning prior to apply.

App Deployment (app-deploy.yml): Builds the Docker container, pushes it to the container registry, and applies the Kubernetes manifests to the GKE cluster.

Repository Structure

.
├── .github/workflows/     # CI/CD pipeline definitions
├── terraform/             # IaC for GCP infrastructure provisioning
├── k8s/                   # Kubernetes manifests (Deployment, Service, Ingress, BackendConfig)
├── app/                   # Web application source code and Dockerfile
├── scripts/               # Bash scripts (e.g., seed_data.sh for DB population)
└── README.md              # Project documentation
