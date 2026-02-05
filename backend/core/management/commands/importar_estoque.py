"""
Management Command para importação de estoque via CSV/XLSX.

Uso:
    python manage.py importar_estoque caminho/arquivo.xlsx
    python manage.py importar_estoque caminho/arquivo.csv --separador=";"

Estrutura esperada do arquivo:
    COD_UNB | SKU | DESCRICAO | LOTE | VALIDADE | QTD

Exemplo:
    COD_UNB,SKU,DESCRICAO,LOTE,VALIDADE,QTD
    UNB01,SKU001,Produto Teste,LOT001,31/12/2026,100
"""

import os
from datetime import datetime, date
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
import pandas as pd

from core.models import UnidadeNegocio, SKU, LoteValidade


class Command(BaseCommand):
    help = 'Importa dados de estoque a partir de arquivo CSV ou XLSX'

    def add_arguments(self, parser):
        parser.add_argument(
            'arquivo',
            type=str,
            help='Caminho para o arquivo CSV ou XLSX'
        )
        parser.add_argument(
            '--separador',
            type=str,
            default=',',
            help='Separador do CSV (padrão: vírgula). Ex: --separador=";"'
        )
        parser.add_argument(
            '--encoding',
            type=str,
            default='utf-8',
            help='Encoding do arquivo CSV (padrão: utf-8). Ex: --encoding="latin-1"'
        )
        parser.add_argument(
            '--sheet',
            type=str,
            default=None,
            help='Nome da aba do Excel (padrão: primeira aba)'
        )
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Apenas valida o arquivo sem importar'
        )
        parser.add_argument(
            '--limpar-lotes',
            action='store_true',
            help='Remove lotes existentes antes de importar (sobrescrita total)'
        )

    def handle(self, *args, **options):
        arquivo = options['arquivo']
        separador = options['separador']
        encoding = options['encoding']
        sheet = options['sheet']
        dry_run = options['dry_run']
        limpar_lotes = options['limpar_lotes']

        # Validação do arquivo
        if not os.path.exists(arquivo):
            raise CommandError(f'Arquivo não encontrado: {arquivo}')

        extensao = os.path.splitext(arquivo)[1].lower()
        if extensao not in ['.csv', '.xlsx', '.xls']:
            raise CommandError(f'Formato não suportado: {extensao}. Use .csv, .xlsx ou .xls')

        self.stdout.write(self.style.NOTICE(f'\n{"="*60}'))
        self.stdout.write(self.style.NOTICE('SKU+ - Importação de Estoque'))
        self.stdout.write(self.style.NOTICE(f'{"="*60}\n'))
        self.stdout.write(f'Arquivo: {arquivo}')
        
        if dry_run:
            self.stdout.write(self.style.WARNING('MODO DRY-RUN: Nenhum dado será salvo\n'))

        # Leitura do arquivo
        try:
            df = self._ler_arquivo(arquivo, extensao, separador, encoding, sheet)
        except Exception as e:
            raise CommandError(f'Erro ao ler arquivo: {e}')

        # Validação das colunas
        colunas_esperadas = ['COD_UNB', 'SKU', 'DESCRICAO', 'LOTE', 'VALIDADE', 'QTD']
        colunas_arquivo = [col.upper().strip() for col in df.columns]
        df.columns = colunas_arquivo

        colunas_faltantes = [col for col in colunas_esperadas if col not in colunas_arquivo]
        if colunas_faltantes:
            raise CommandError(
                f'Colunas obrigatórias não encontradas: {", ".join(colunas_faltantes)}\n'
                f'Colunas no arquivo: {", ".join(colunas_arquivo)}'
            )

        self.stdout.write(f'Total de linhas: {len(df)}\n')

        # Processa importação
        resultado = self._processar_importacao(df, dry_run, limpar_lotes)

        # Exibe resumo
        self._exibir_resumo(resultado)

    def _ler_arquivo(self, arquivo, extensao, separador, encoding, sheet):
        """Lê arquivo CSV ou Excel e retorna DataFrame."""
        if extensao == '.csv':
            df = pd.read_csv(
                arquivo, 
                sep=separador, 
                encoding=encoding,
                dtype=str,  # Lê tudo como string para evitar problemas
                keep_default_na=False
            )
        else:
            df = pd.read_excel(
                arquivo,
                sheet_name=sheet if sheet else 0,
                dtype=str,
                keep_default_na=False
            )
        
        # Remove espaços em branco nas colunas e valores
        df.columns = df.columns.str.strip()
        df = df.apply(lambda x: x.str.strip() if x.dtype == "object" else x)
        
        return df

    def _parse_data(self, valor_data):
        """
        Converte string de data para objeto date.
        Aceita formatos: DD/MM/YYYY, DD-MM-YYYY, YYYY-MM-DD
        """
        if pd.isna(valor_data) or str(valor_data).strip() == '':
            return None

        valor = str(valor_data).strip()
        
        # Tenta diferentes formatos
        formatos = [
            '%d/%m/%Y',   # 31/12/2026
            '%d-%m-%Y',   # 31-12-2026
            '%Y-%m-%d',   # 2026-12-31
            '%d/%m/%y',   # 31/12/26
            '%Y/%m/%d',   # 2026/12/31
        ]
        
        for fmt in formatos:
            try:
                return datetime.strptime(valor, fmt).date()
            except ValueError:
                continue
        
        raise ValueError(f'Formato de data inválido: {valor}')

    def _parse_quantidade(self, valor_qtd):
        """Converte valor de quantidade para inteiro."""
        if pd.isna(valor_qtd) or str(valor_qtd).strip() == '':
            return 0
        
        valor = str(valor_qtd).strip()
        
        # Remove separadores de milhar e converte vírgula para ponto
        valor = valor.replace('.', '').replace(',', '.')
        
        try:
            return int(float(valor))
        except ValueError:
            raise ValueError(f'Quantidade inválida: {valor_qtd}')

    def _gerar_lote_automatico(self):
        """Gera número de lote automático baseado na data."""
        return f"IMP_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

    def _processar_importacao(self, df, dry_run, limpar_lotes):
        """Processa cada linha do DataFrame e importa os dados."""
        resultado = {
            'sucesso': 0,
            'falhas': 0,
            'skus_criados': 0,
            'skus_atualizados': 0,
            'lotes_criados': 0,
            'lotes_atualizados': 0,
            'unidades_nao_encontradas': set(),
            'erros': []
        }

        # Cache de unidades para evitar queries repetidas
        unidades_cache = {
            u.codigo_unb: u 
            for u in UnidadeNegocio.objects.filter(ativo=True)
        }

        # Cache de SKUs processados nesta importação
        skus_processados = {}

        # Lotes a limpar (se opção ativada)
        if limpar_lotes and not dry_run:
            self.stdout.write(self.style.WARNING('Removendo lotes existentes...\n'))

        for idx, row in df.iterrows():
            linha_num = idx + 2  # +2 porque pandas é 0-indexed e tem header
            
            try:
                # Extrai dados da linha
                cod_unb = str(row.get('COD_UNB', '')).strip()
                codigo_sku = str(row.get('SKU', '')).strip()
                descricao = str(row.get('DESCRICAO', '')).strip()
                numero_lote = str(row.get('LOTE', '')).strip()
                validade_str = str(row.get('VALIDADE', '')).strip()
                qtd_str = str(row.get('QTD', '')).strip()

                # Validações básicas
                if not cod_unb:
                    raise ValueError('COD_UNB vazio')
                if not codigo_sku:
                    raise ValueError('SKU vazio')
                if not descricao:
                    raise ValueError('DESCRICAO vazia')
                if not validade_str:
                    raise ValueError('VALIDADE vazia')

                # Busca unidade
                unidade = unidades_cache.get(cod_unb)
                if not unidade:
                    resultado['unidades_nao_encontradas'].add(cod_unb)
                    raise ValueError(f'Unidade não encontrada: {cod_unb}')

                # Parse de data e quantidade
                data_validade = self._parse_data(validade_str)
                if not data_validade:
                    raise ValueError('Data de validade inválida')
                
                quantidade = self._parse_quantidade(qtd_str)

                # Gera lote automático se vazio
                if not numero_lote:
                    numero_lote = self._gerar_lote_automatico()

                if not dry_run:
                    with transaction.atomic():
                        # Cria ou atualiza SKU
                        cache_key = f"{cod_unb}_{codigo_sku}"
                        
                        if cache_key in skus_processados:
                            sku = skus_processados[cache_key]
                            sku_criado = False
                        else:
                            sku, sku_criado = SKU.objects.update_or_create(
                                codigo_sku=codigo_sku,
                                unidade_negocio=unidade,
                                defaults={
                                    'nome_produto': descricao,
                                    'ativo': True
                                }
                            )
                            skus_processados[cache_key] = sku
                            
                            if sku_criado:
                                resultado['skus_criados'] += 1
                            else:
                                resultado['skus_atualizados'] += 1

                        # Limpa lotes existentes do SKU (se opção ativada)
                        if limpar_lotes and cache_key not in skus_processados:
                            sku.lotes.all().delete()

                        # Cria ou atualiza Lote
                        lote, lote_criado = LoteValidade.objects.update_or_create(
                            sku=sku,
                            numero_lote=numero_lote,
                            defaults={
                                'data_validade': data_validade,
                                'qtd_estoque': quantidade,
                                'ativo': True
                            }
                        )
                        
                        if lote_criado:
                            resultado['lotes_criados'] += 1
                        else:
                            resultado['lotes_atualizados'] += 1

                resultado['sucesso'] += 1

                # Progress indicator a cada 100 linhas
                if (idx + 1) % 100 == 0:
                    self.stdout.write(f'  Processadas {idx + 1} linhas...')

            except Exception as e:
                resultado['falhas'] += 1
                erro_msg = f'Linha {linha_num}: {str(e)}'
                resultado['erros'].append(erro_msg)
                
                # Mostra erro se for dry-run ou se houver menos de 20 erros
                if dry_run or len(resultado['erros']) <= 20:
                    self.stdout.write(self.style.ERROR(f'  ✗ {erro_msg}'))

        return resultado

    def _exibir_resumo(self, resultado):
        """Exibe resumo da importação."""
        self.stdout.write(self.style.NOTICE(f'\n{"="*60}'))
        self.stdout.write(self.style.NOTICE('RESUMO DA IMPORTAÇÃO'))
        self.stdout.write(self.style.NOTICE(f'{"="*60}\n'))

        # Sucessos
        self.stdout.write(
            self.style.SUCCESS(f'✓ Linhas importadas com sucesso: {resultado["sucesso"]}')
        )
        
        if resultado['sucesso'] > 0:
            self.stdout.write(f'  • SKUs criados: {resultado["skus_criados"]}')
            self.stdout.write(f'  • SKUs atualizados: {resultado["skus_atualizados"]}')
            self.stdout.write(f'  • Lotes criados: {resultado["lotes_criados"]}')
            self.stdout.write(f'  • Lotes atualizados: {resultado["lotes_atualizados"]}')

        # Falhas
        if resultado['falhas'] > 0:
            self.stdout.write(
                self.style.ERROR(f'\n✗ Linhas com falha: {resultado["falhas"]}')
            )

        # Unidades não encontradas
        if resultado['unidades_nao_encontradas']:
            self.stdout.write(
                self.style.WARNING(
                    f'\n⚠ Unidades não encontradas: {", ".join(resultado["unidades_nao_encontradas"])}'
                )
            )
            self.stdout.write(
                '  Cadastre essas unidades antes de importar novamente.'
            )

        # Lista de erros (limitada)
        if resultado['erros']:
            total_erros = len(resultado['erros'])
            if total_erros > 20:
                self.stdout.write(
                    self.style.WARNING(f'\n⚠ Exibindo primeiros 20 de {total_erros} erros:')
                )
            else:
                self.stdout.write(self.style.WARNING('\nDetalhes dos erros:'))
            
            for erro in resultado['erros'][:20]:
                self.stdout.write(f'  • {erro}')

        self.stdout.write(self.style.NOTICE(f'\n{"="*60}\n'))
