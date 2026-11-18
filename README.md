# M1 Infrastruktur mit Terraform

Baut VPC, öffentliches Subnetz, Internet Gateway, Route Table, vier Security Groups und
fünf Ubuntu-24.04-Instanzen (dns1, dns2, gitlab, runner, ldap) laut Spezifikation.

## Vorbereitung
1. Terraform installieren (>= 1.5).
2. Learner Lab: "AWS Details" → "AWS CLI" → "Show" öffnen und die drei Werte als Umgebungsvariablen setzen
   (ändern sich bei jeder Lab-Sitzung):

   **Linux / macOS (Bash/Zsh):**
   ```bash
   export AWS_ACCESS_KEY_ID=...
   export AWS_SECRET_ACCESS_KEY=...
   export AWS_SESSION_TOKEN=...
   ```

   **Windows (PowerShell):**
   ```powershell
   $env:AWS_ACCESS_KEY_ID="..."
   $env:AWS_SECRET_ACCESS_KEY="..."
   $env:AWS_SESSION_TOKEN="..."
   ```
3. `cp terraform.tfvars.example terraform.tfvars` und ausfüllen
   (öffentliche IPs der Teamgeräte, SSH-Public-Keys, `use_custom_dhcp = false`).

## Aufbau
```
terraform init
terraform plan
terraform apply
```
Danach zeigt `terraform output` die öffentlichen IPs und SSH-Befehle.

## DHCP-Optionen (Reihenfolge wichtig)
1. Auf dns1 und dns2 BIND installieren und konfigurieren.
2. `use_custom_dhcp = true` setzen und `terraform apply` ausführen.
3. Die VMs übernehmen die neuen DNS-Server nach einem Neustart (`sudo reboot`).
4. Test: `dig gitlab.cicd.internal` auf jeder VM.

## Alltag
- **Herunterfahren:** Instanzen in der Konsole stoppen (nicht terminieren) oder `sudo poweroff`.
- **Nach dem Start** haben die VMs neue öffentliche IPs: `terraform apply -refresh-only`, dann `terraform output`.
- **Ändern sich die Team-IPs**, `team_ips` anpassen und `terraform apply`. Das ändert nur Security Groups.
- **`terraform destroy`** löscht alles inklusive aller GitLab-Daten. Nur für einen echten Neuaufbau.
- `terraform.tfstate` liegt lokal: nur eine Person führt `apply` aus, die Datei nicht ins Git.
