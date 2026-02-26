Flowchart LR
    %% Define styles mimicking GCP colors
    classDef internet fill:#fff,stroke:#4285F4,stroke-width:2px,color:#000
    classDef lb fill:#e8f0fe,stroke:#4285F4,stroke-width:2px,color:#000
    classDef gke fill:#e8f0fe,stroke:#4285F4,stroke-width:2px,color:#000
    classDef vm fill:#fef7e0,stroke:#F4B400,stroke-width:2px,color:#000
    classDef storage fill:#e8f0fe,stroke:#4285F4,stroke-width:2px,color:#000
    classDef subnet fill:none,stroke:#9aa0a6,stroke-width:2px,stroke-dasharray: 5 5

    %% Entities
    Internet((fa:fa-globe Public \nInternet)):::internet
    
    LB[fa:fa-sitemap GCP Cloud \nLoad Balancer]:::lb

    subgraph PrivateSubnet [Private Subnet]
        direction TB
        GKE[fa:fa-cubes Google Kubernetes \nEngine \n(Containerized App)]:::gke
    end
    class PrivateSubnet subnet

    subgraph PublicSubnet [Public Subnet]
        direction TB
        VM[fa:fa-server Compute Engine VM \n(MongoDB 4.4)\nOpen Port 22]:::vm
    end
    class PublicSubnet subnet

    Bucket[(fa:fa-database Cloud Storage \nBackup Bucket)]:::storage

    %% Relationships
    Internet -- "HTTP/HTTPS" --> LB
    LB -- "Routes Traffic" --> GKE
    GKE -- "TCP 27017 (Internal)" --> VM
    VM -- "Automated Script" --> Bucket
