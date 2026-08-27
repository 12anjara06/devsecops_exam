# Mini Site — Déploiement GitOps (ArgoCD + Kubernetes)

Ce dépôt contient le mini site vitrine (HTML/CSS statique) + tout ce qu'il faut
pour le déployer sur un cluster Kubernetes local (minikube ou k3s) piloté par
ArgoCD en mode GitOps : chaque `git push` sur ce repo est détecté par ArgoCD,
qui resynchronise automatiquement le cluster.

```
.
├── site/                 # Le site statique (HTML/CSS)
│   ├── index.html
│   └── style.css
├── Dockerfile            # Empaquette le site dans une image Nginx
├── k8s/                  # Manifestes surveillés par ArgoCD
│   ├── deployment.yaml   # 4 replicas
│   ├── service.yaml
│   └── ingress.yaml      # Ingress Nginx
└── argocd/
    └── application.yaml  # Définition de l'App ArgoCD
```

## Schéma du flux

```
  git push (site modifié)
        │
        ▼
  GitHub (ce repo)
        │  ArgoCD "poll" le repo (par défaut toutes les 3 min,
        │  ou instantané si tu configures un webhook GitHub)
        ▼
  ArgoCD détecte un diff entre le repo et le cluster
        │
        ▼
  ArgoCD applique k8s/*.yaml → Deployment (4 pods) + Service + Ingress
        │
        ▼
  Nginx Ingress Controller (minikube/k3s) route le trafic vers les pods
        │
        ▼
  http://mini-site.local → ton site, en local, à jour
```

---

## 0. Prérequis

- `git`, `docker`, `kubectl`
- `minikube` **ou** `k3s` (les deux marchent, les commandes ci-dessous sont pour minikube)
- Un compte GitHub

## 1. Créer le repo GitHub et pousser le projet

```bash
cd gitops-site
git init
git add .
git commit -m "Initial commit: mini site + manifests k8s + argocd app"
git branch -M main
git remote add origin https://github.com/TON-UTILISATEUR/mini-site-gitops.git
git push -u origin main
```

⚠️ Ensuite, édite `argocd/application.yaml` et remplace `repoURL` par
l'URL réelle de ton repo, puis re-commit/push.

## 2. Démarrer le cluster local (minikube)

```bash
minikube start
minikube addons enable ingress    # installe le Nginx Ingress Controller
```

Pour k3s, l'Ingress Nginx est en général déjà inclus via Traefik par défaut ;
si tu veux du "vrai" Nginx Ingress sur k3s, installe-le avec Helm :
`helm install nginx-ingress ingress-nginx/ingress-nginx`.

## 3. Builder l'image Docker directement dans le cluster

Pour éviter d'avoir besoin d'un registre Docker externe en local, on construit
l'image directement dans le daemon Docker de minikube :

```bash
eval $(minikube docker-env)
docker build -t mini-site:latest .
```

`imagePullPolicy: IfNotPresent` dans `k8s/deployment.yaml` permet à
Kubernetes d'utiliser cette image locale sans aller la chercher sur un
registre distant.

> Si tu préfères un vrai registre (Docker Hub, GHCR...), build + push l'image
> là-bas et mets à jour `image:` dans `k8s/deployment.yaml` avec le tag complet.

## 4. Installer ArgoCD dans le cluster

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Attendre que tous les pods soient Running
kubectl get pods -n argocd -w
```

Récupérer le mot de passe admin initial :

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Accéder à l'interface :

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# puis ouvrir https://localhost:8080  (user: admin)
```

## 5. Déclarer l'Application ArgoCD

```bash
kubectl apply -f argocd/application.yaml
```

ArgoCD va maintenant surveiller le dossier `k8s/` de ton repo GitHub et
créer automatiquement : le `Deployment` (4 replicas), le `Service` et
l'`Ingress`.

Vérifier :

```bash
kubectl get applications -n argocd
kubectl get pods -l app=mini-site
kubectl get ingress
```

## 6. Accéder au site

```bash
echo "$(minikube ip) mini-site.local" | sudo tee -a /etc/hosts
curl http://mini-site.local
# ou ouvrir http://mini-site.local dans le navigateur
```

## 7. Le workflow GitOps en action

À partir de maintenant, pour déployer une modification :

```bash
# modifie site/index.html ou k8s/deployment.yaml (ex: replicas: 6)
git add .
git commit -m "Change couleur accent"
git push
```

ArgoCD détecte le changement (poll auto ~3 min, ou clique "Refresh" dans
l'UI pour forcer), et resynchronise le cluster tout seul — pas de
`kubectl apply` manuel nécessaire. C'est ça, GitOps : **le repo Git est la
source de vérité, ArgoCD fait converger le cluster vers cet état**.

### Note sur l'image Docker

Ce setup GitOps synchronise les **manifestes Kubernetes**. Si tu modifies le
*contenu du site* (HTML/CSS), il faut aussi reconstruire l'image
(`docker build` étape 3) puisque le tag `latest` ne se met pas à jour tout
seul. Pour un pipeline 100% automatique (build + push image + update du tag
dans le repo), l'étape suivante serait d'ajouter une CI (GitHub Actions) qui
build/push l'image vers un registre et met à jour `k8s/deployment.yaml` —
c'est le pattern "GitOps avec CI externe", une bonne évolution une fois ce
premier pipeline maîtrisé.
