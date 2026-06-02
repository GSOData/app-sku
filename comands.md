ENVIO AO GITHUB



* git add .
* git commit -m ""
* git push





ATUALIZAR VPS



* cd /var/www/app\_sku
* git pull origin main
* sudo systemctl restart gunicorn



BUILD WEB (dentro do vscode)



* flutter build web
* scp -r build/web root@31.97.83.219:/var/www/app\_sku/







ATIVAR VENV VPS

* source venv/bin/activate





ACESSOS HOSTINGER



* ssh root@31.97.83.219
* Senha root (Hostinger): yd1\&Yx.A8g9Kn5?B
* senha skuplus\_db: t(N45eSh0%Fep\*%yG=(K

