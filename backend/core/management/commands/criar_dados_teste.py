"""
Management Command para criar dados iniciais de teste.

Uso:
    python manage.py criar_dados_teste

Cria:
- 3 Unidades de Negócio
- 1 Usuário admin
- 1 Configuração de Alerta global
"""

from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from core.models import UnidadeNegocio, ConfiguracaoAlerta, UsuarioUnidade

Usuario = get_user_model()


class Command(BaseCommand):
    help = 'Cria dados iniciais para teste do sistema SKU+'

    def handle(self, *args, **options):
        self.stdout.write(self.style.NOTICE('\n' + '='*60))
        self.stdout.write(self.style.NOTICE('SKU+ - Criação de Dados de Teste'))
        self.stdout.write(self.style.NOTICE('='*60 + '\n'))

        # Criar Unidades de Negócio
        unidades_data = [
            {'codigo_unb': 'UNB01', 'nome': 'Filial Centro', 'endereco': 'Rua Principal, 100 - Centro'},
            {'codigo_unb': 'UNB02', 'nome': 'Filial Norte', 'endereco': 'Av. Norte, 500 - Zona Norte'},
            {'codigo_unb': 'UNB03', 'nome': 'CD Principal', 'endereco': 'Rod. Industrial, km 10'},
        ]

        unidades_criadas = []
        for data in unidades_data:
            unidade, created = UnidadeNegocio.objects.get_or_create(
                codigo_unb=data['codigo_unb'],
                defaults=data
            )
            unidades_criadas.append(unidade)
            status = 'criada' if created else 'já existe'
            self.stdout.write(f'  • Unidade {data["codigo_unb"]}: {status}')

        # Criar Configuração de Alerta Global
        config, created = ConfiguracaoAlerta.objects.get_or_create(
            unidade=None,
            defaults={
                'dias_para_critico': 30,
                'dias_para_pre_bloqueio': 45,
            }
        )
        status = 'criada' if created else 'já existe'
        self.stdout.write(f'\n  • Configuração de Alerta Global: {status}')
        self.stdout.write(f'    - Crítico: {config.dias_para_critico} dias')
        self.stdout.write(f'    - Pré-Bloqueio: {config.dias_para_pre_bloqueio} dias')

        # Criar usuário admin
        admin_user, created = Usuario.objects.get_or_create(
            username='admin',
            defaults={
                'email': 'admin@skuplus.com',
                'first_name': 'Administrador',
                'last_name': 'Sistema',
                'cargo': 'Administrador',
                'is_staff': True,
                'is_superuser': True,
            }
        )
        
        if created:
            admin_user.set_password('admin123')
            admin_user.save()
            self.stdout.write(self.style.SUCCESS(f'\n  • Usuário admin criado'))
            self.stdout.write(f'    - Username: admin')
            self.stdout.write(f'    - Senha: admin123')
        else:
            self.stdout.write(f'\n  • Usuário admin: já existe')

        # Criar usuário operador
        operador, created = Usuario.objects.get_or_create(
            username='operador',
            defaults={
                'email': 'operador@skuplus.com',
                'first_name': 'João',
                'last_name': 'Operador',
                'cargo': 'Operador de Estoque',
                'is_staff': False,
                'is_superuser': False,
            }
        )
        
        if created:
            operador.set_password('oper123')
            operador.save()
            
            # Vincula apenas às filiais (não ao CD)
            for unidade in unidades_criadas[:2]:  # UNB01 e UNB02
                UsuarioUnidade.objects.get_or_create(
                    usuario=operador,
                    unidade=unidade,
                    defaults={'papel': 'OPERADOR'}
                )
            
            self.stdout.write(self.style.SUCCESS(f'\n  • Usuário operador criado'))
            self.stdout.write(f'    - Username: operador')
            self.stdout.write(f'    - Senha: oper123')
            self.stdout.write(f'    - Acesso: UNB01, UNB02 (sem acesso ao CD)')
        else:
            self.stdout.write(f'\n  • Usuário operador: já existe')

        # Resumo
        self.stdout.write(self.style.NOTICE('\n' + '='*60))
        self.stdout.write(self.style.SUCCESS('Dados de teste criados com sucesso!'))
        self.stdout.write(self.style.NOTICE('='*60))
        self.stdout.write('\nPróximos passos:')
        self.stdout.write('  1. Execute as migrations: python manage.py migrate')
        self.stdout.write('  2. Importe o estoque: python manage.py importar_estoque import_files/exemplo_estoque.csv')
        self.stdout.write('  3. Inicie o servidor: python manage.py runserver')
        self.stdout.write('  4. Acesse: http://localhost:8000/admin/')
        self.stdout.write('\n')
