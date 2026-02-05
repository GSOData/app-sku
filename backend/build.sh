#!/usr/bin/env bash
# Sair se der erro
set -o errexit

# Instalar dependências
pip install -r requirements.txt

# Coletar arquivos estáticos (CSS/JS)
python manage.py collectstatic --no-input

# Rodar migrações no banco de dados
python manage.py migrate