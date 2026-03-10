"""
Services para processamento de dados do SKU+.

Inclui:
- EstoqueImportService: Importação de planilhas de estoque
- definir_categoria: Classificação automática de SKUs por palavras-chave
"""

import pandas as pd
from io import BytesIO
from datetime import datetime
from typing import Tuple, Dict, Any
from django.db import transaction
from django.db.models import Sum
from django.utils import timezone

from .models import SKU, LoteValidade, UnidadeNegocio


# =============================================================================
# REGRAS DE CLASSIFICAÇÃO POR CATEGORIA
# =============================================================================
REGRAS_CATEGORIA = {
    'CERVEJA': [
        'SKOL', 'BRAHMA', 'ANTARCTICA PILSEN', 'ANTARCTICA SUBZERO', 
        'ORIGINAL', 'BUDWEISER', 'MICHELOB', 'CORONA', 'CORONITA', 
        'STELLA', 'SPATEN', 'BOHEMIA', 'MALZBIER'
    ],
    'REFRIGERANTE': [
        'GUARANA', 'PEPSI', 'SUKITA', 'SODA', 'H2OH', 'TONICA'
    ],
    'ICE E MISTAS': [
        'BEATS', 'ICE'
    ],
    'ÁGUA': [
        'INDAIA', 'PETROPOLIS AGUA', 'AGUA MIN'
    ],
    'SUCO': [
        'TIAL'
    ],
    'ISOTÔNICO': [
        'GATORADE'
    ],
    'ENERGÉTICO': [
        'RED BULL'
    ],
    'DESTILADO': [
        'JOHNNIE WALKER', 'ABSOLUT', 'SMIRNOFF ORIGINAL', 'MONTILLA', 
        'BALLANTINES', 'PIRASSUNUNGA', 'PASSPORT', 'DOMECQ', 'PITU'
    ],
    'VINHO': [
        'QUINTA DO MORGADO', 'VINHO'
    ],
    'BOMBONIERE': [
        'TRIDENT', 'HALLS', 'CHICLETE'
    ],
    'LIMPEZA': [
        'YPE'
    ],
    'ACESSÓRIOS': [
        'GARRAFEIRA', 'CERVEGELA'
    ],
}

# Ordem de verificação (ICE E MISTAS antes de DESTILADO para evitar conflitos)
ORDEM_CATEGORIAS = [
    'CERVEJA', 'REFRIGERANTE', 'ICE E MISTAS', 'ÁGUA', 'SUCO',
    'ISOTÔNICO', 'ENERGÉTICO', 'DESTILADO', 'VINHO', 
    'BOMBONIERE', 'LIMPEZA', 'ACESSÓRIOS'
]


def definir_categoria(nome_produto: str) -> str:
    """
    Define a categoria de um produto baseado em palavras-chave no nome.
    
    Args:
        nome_produto: Nome do produto para classificar
        
    Returns:
        String com a categoria (ex: 'CERVEJA', 'REFRIGERANTE', 'OUTROS')
    """
    if not nome_produto:
        return 'OUTROS'
    
    nome_upper = nome_produto.upper()
    
    # Verifica na ordem definida para evitar conflitos
    for categoria in ORDEM_CATEGORIAS:
        palavras_chave = REGRAS_CATEGORIA.get(categoria, [])
        for palavra in palavras_chave:
            if palavra in nome_upper:
                return categoria
    
    return 'OUTROS'


class EstoqueImportService:
    """
    Service para importação de planilhas de estoque.
    
    Processa dois tipos de arquivo:
    1. Grade 020502: Estoque total diário (sem validade)
    2. Contagens: Conciliação de validades semanais
    """
    
    # Mapeamento de colunas para Grade 020502
    COLUNAS_GRADE_020502 = {
        'Produto': 'codigo_sku',
        'Descricao': 'nome_produto',
        'Unidade': 'unidade_medida',
        'Fator': 'fator_conversao',
        'Inventario': 'estoque_display',
        'Qtd Contagem': 'qtd_estoque',
    }
    
    # Mapeamento de colunas para Contagens
    COLUNAS_CONTAGENS = {
        'Código Item': 'codigo_sku',
        'Validade Aferida': 'data_validade',
        'Quantidade Cx': 'qtd_caixas',
        'Quantidade Unidade': 'qtd_unidades',
    }
    
    def __init__(self, unidade_negocio_id: int):
        """
        Inicializa o service com a unidade de negócio.
        
        Args:
            unidade_negocio_id: ID da unidade de negócio para vincular os dados
        """
        self.unidade_negocio = UnidadeNegocio.objects.get(id=unidade_negocio_id)
        self.errors = []
        self.warnings = []
        self.processed_count = 0
        self.created_count = 0
        self.updated_count = 0
    
    def _read_file(self, file) -> pd.DataFrame:
        """
        Lê arquivo Excel ou CSV e retorna DataFrame.
        
        Args:
            file: Arquivo upload (InMemoryUploadedFile)
            
        Returns:
            DataFrame com os dados do arquivo
        """
        filename = file.name.lower()
        
        try:
            if filename.endswith('.csv'):
                # Tenta diferentes encodings
                for encoding in ['utf-8', 'latin-1', 'cp1252']:
                    try:
                        file.seek(0)
                        df = pd.read_csv(file, encoding=encoding, sep=None, engine='python')
                        break
                    except UnicodeDecodeError:
                        continue
                else:
                    raise ValueError("Não foi possível decodificar o arquivo CSV")
            else:
                # Excel (.xlsx, .xls)
                file.seek(0)
                df = pd.read_excel(file)
            
            return df
            
        except Exception as e:
            raise ValueError(f"Erro ao ler arquivo: {str(e)}")
    
    def _normalize_columns(self, df: pd.DataFrame, column_mapping: dict) -> pd.DataFrame:
        """
        Normaliza nomes de colunas do DataFrame.
        
        Args:
            df: DataFrame original
            column_mapping: Dicionário de mapeamento fonte->destino
            
        Returns:
            DataFrame com colunas renomeadas
        """
        # Remove espaços extras dos nomes das colunas
        df.columns = df.columns.str.strip()
        
        # Mapeia colunas encontradas
        rename_map = {}
        for source, target in column_mapping.items():
            # Busca case-insensitive
            matches = [col for col in df.columns if col.lower() == source.lower()]
            if matches:
                rename_map[matches[0]] = target
        
        return df.rename(columns=rename_map)
    
    def _parse_date(self, value) -> datetime.date:
        """
        Converte valor para date.
        
        Args:
            value: Valor a ser convertido (string, datetime, date)
            
        Returns:
            Date ou None se inválido
        """
        if pd.isna(value) or value is None or value == '':
            return None
        
        # Se já for date/datetime
        if isinstance(value, datetime):
            return value.date()
        if hasattr(value, 'date'):
            return value.date()
        
        # Tenta parsear string
        date_formats = [
            '%d/%m/%Y', '%Y-%m-%d', '%d-%m-%Y',
            '%d/%m/%y', '%Y/%m/%d', '%m/%d/%Y'
        ]
        
        value_str = str(value).strip()
        for fmt in date_formats:
            try:
                return datetime.strptime(value_str, fmt).date()
            except ValueError:
                continue
        
        return None
    
    @transaction.atomic
    def processar_grade_020502(self, file) -> Dict[str, Any]:
        """
        Processa planilha de Grade 020502 (Estoque Total Diário).
        
        Colunas esperadas:
        - Produto: Código SKU
        - Descricao: Nome do produto
        - Unidade: Unidade de medida (cx, un, etc)
        - Fator: Fator de conversão
        - Inventario: Texto original (ex: "388/06")
        - Qtd Contagem: Quantidade total em unidades
        
        Args:
            file: Arquivo upload
            
        Returns:
            Dict com resultado do processamento
        """
        self._reset_counters()
        
        try:
            df = self._read_file(file)
            df = self._normalize_columns(df, self.COLUNAS_GRADE_020502)
            
            # Verifica colunas obrigatórias
            required_cols = ['codigo_sku', 'qtd_estoque']
            missing_cols = [col for col in required_cols if col not in df.columns]
            if missing_cols:
                raise ValueError(f"Colunas obrigatórias não encontradas: {missing_cols}")
            
            # Preenche NaN com valores padrão
            df['qtd_estoque'] = pd.to_numeric(df['qtd_estoque'], errors='coerce').fillna(0).astype(int)
            df['fator_conversao'] = pd.to_numeric(df.get('fator_conversao', 1), errors='coerce').fillna(1).astype(int)
            df['nome_produto'] = df.get('nome_produto', '').fillna('Sem descrição')
            df['unidade_medida'] = df.get('unidade_medida', 'UN').fillna('UN')
            df['estoque_display'] = df.get('estoque_display', '').fillna('')
            
            for idx, row in df.iterrows():
                try:
                    codigo_sku = str(row['codigo_sku']).strip()
                    if not codigo_sku or codigo_sku == 'nan':
                        continue
                    
                    # Busca ou cria SKU
                    sku, created = SKU.objects.get_or_create(
                        codigo_sku=codigo_sku,
                        unidade_negocio=self.unidade_negocio,
                        defaults={
                            'nome_produto': str(row['nome_produto']).strip(),
                            'unidade_medida': str(row['unidade_medida']).strip().upper(),
                            'fator_conversao': int(row['fator_conversao']),
                            'categoria': definir_categoria(str(row['nome_produto'])),
                        }
                    )
                    
                    if not created:
                        # Atualiza dados do SKU
                        sku.nome_produto = str(row['nome_produto']).strip()
                        sku.unidade_medida = str(row['unidade_medida']).strip().upper()
                        sku.fator_conversao = int(row['fator_conversao'])
                        # Reclassifica categoria se ainda for OUTROS ou vazia
                        if not sku.categoria or sku.categoria == 'OUTROS':
                            sku.categoria = definir_categoria(sku.nome_produto)
                        sku.save()
                        self.updated_count += 1
                    else:
                        self.created_count += 1
                    
                    # Busca ou cria Lote BASE (sem validade)
                    lote, lote_created = LoteValidade.objects.get_or_create(
                        sku=sku,
                        numero_lote='BASE',
                        data_validade=None,
                        defaults={
                            'qtd_estoque': int(row['qtd_estoque']),
                            'estoque_display': str(row['estoque_display']).strip(),
                        }
                    )
                    
                    if not lote_created:
                        # Atualiza quantidade
                        lote.qtd_estoque = int(row['qtd_estoque'])
                        lote.estoque_display = str(row['estoque_display']).strip()
                        lote.save()
                    
                    self.processed_count += 1
                    
                except Exception as e:
                    self.errors.append(f"Linha {idx + 2}: {str(e)}")
            
            return self._build_result('Grade 020502')
            
        except Exception as e:
            return {
                'success': False,
                'error': str(e),
                'processed': 0,
            }
    
    @transaction.atomic
    def processar_contagens(self, file) -> Dict[str, Any]:
        """
        Processa planilha de Contagens (Conciliação de Validades).
        
        Colunas esperadas:
        - Código Item: Código SKU
        - Validade Aferida: Data de validade
        - Quantidade Cx: Quantidade em caixas
        - Quantidade Unidade: Quantidade em unidades
        
        REGRAS DE NEGÓCIO:
        - A soma dos lotes com validade NÃO pode ultrapassar o total da 020502
        - O lote BASE é recalculado como: Total 020502 - Soma(lotes com validade)
        - Se a soma ultrapassar, a quantidade é limitada ao disponível
        
        Args:
            file: Arquivo upload
            
        Returns:
            Dict com resultado do processamento
        """
        self._reset_counters()
        
        try:
            df = self._read_file(file)
            df = self._normalize_columns(df, self.COLUNAS_CONTAGENS)
            
            # Verifica colunas obrigatórias
            required_cols = ['codigo_sku', 'data_validade']
            missing_cols = [col for col in required_cols if col not in df.columns]
            if missing_cols:
                raise ValueError(f"Colunas obrigatórias não encontradas: {missing_cols}")
            
            # Preenche NaN com valores padrão
            df['qtd_caixas'] = pd.to_numeric(df.get('qtd_caixas', 0), errors='coerce').fillna(0).astype(int)
            df['qtd_unidades'] = pd.to_numeric(df.get('qtd_unidades', 0), errors='coerce').fillna(0).astype(int)
            
            # Agrupa por SKU para processar todas as validades juntas
            skus_processados = {}
            
            for idx, row in df.iterrows():
                try:
                    # 1. CORREÇÃO DO CÓDIGO (Remove .0 do final se existir)
                    raw_codigo = str(row['codigo_sku']).strip()
                    if not raw_codigo or raw_codigo == 'nan':
                        continue
                    
                    # Converte "1388.0" para "1388"
                    if raw_codigo.endswith('.0'):
                        codigo_sku = raw_codigo[:-2]
                    else:
                        codigo_sku = raw_codigo
                    
                    # Busca SKU existente
                    try:
                        sku = SKU.objects.get(
                            codigo_sku=codigo_sku,
                            unidade_negocio=self.unidade_negocio,
                            ativo=True
                        )
                    except SKU.DoesNotExist:
                        self.warnings.append(
                            f"Linha {idx + 2}: SKU '{codigo_sku}' não encontrado no Estoque Total"
                        )
                        continue
                    
                    # 2. PARSEIA DATA DE VALIDADE
                    data_validade = self._parse_date(row['data_validade'])
                    if data_validade is None:
                        self.warnings.append(
                            f"Linha {idx + 2}: Data de validade vazia ou inválida para SKU '{codigo_sku}'"
                        )
                        continue
                    
                    # Calcula quantidade total em unidades
                    qtd_caixas = int(row['qtd_caixas'])
                    qtd_unidades = int(row['qtd_unidades'])
                    qtd_total = (qtd_caixas * sku.fator_conversao) + qtd_unidades
                    
                    # Agrupa por SKU
                    if codigo_sku not in skus_processados:
                        skus_processados[codigo_sku] = {
                            'sku': sku,
                            'lotes': []
                        }
                    
                    skus_processados[codigo_sku]['lotes'].append({
                        'data_validade': data_validade,
                        'qtd_total': qtd_total,
                        'linha': idx + 2
                    })
                    
                except Exception as e:
                    self.errors.append(f"Linha {idx + 2}: {str(e)}")
            
            # Processa cada SKU respeitando o limite da 020502
            for codigo_sku, dados in skus_processados.items():
                sku = dados['sku']
                lotes_validade = dados['lotes']
                
                # Busca o total disponível no lote BASE (020502)
                try:
                    lote_base = LoteValidade.objects.get(
                        sku=sku,
                        numero_lote='BASE'
                    )
                    total_disponivel = lote_base.qtd_estoque
                except LoteValidade.DoesNotExist:
                    self.warnings.append(
                        f"SKU '{codigo_sku}': Lote BASE não encontrado. Importe a planilha 020502 primeiro."
                    )
                    continue
                
                # Soma dos lotes com validade que já existem (excluindo os que vamos atualizar)
                datas_validade_novas = [l['data_validade'] for l in lotes_validade]
                soma_lotes_existentes = LoteValidade.objects.filter(
                    sku=sku,
                    ativo=True,
                    data_validade__isnull=False
                ).exclude(
                    data_validade__in=datas_validade_novas
                ).aggregate(
                    total=Sum('qtd_estoque')
                )['total'] or 0
                
                # Calcula quanto resta para os novos lotes
                disponivel_para_novos = total_disponivel - soma_lotes_existentes
                
                # Ordena lotes por data de validade (mais próximo primeiro - FEFO)
                lotes_validade.sort(key=lambda x: x['data_validade'])
                
                soma_novos_lotes = 0
                
                for lote_info in lotes_validade:
                    data_validade = lote_info['data_validade']
                    qtd_solicitada = lote_info['qtd_total']
                    linha = lote_info['linha']
                    
                    # Verifica se ainda há quantidade disponível
                    qtd_restante = disponivel_para_novos - soma_novos_lotes
                    
                    if qtd_restante <= 0:
                        self.warnings.append(
                            f"Linha {linha}: SKU '{codigo_sku}' - Quantidade excede o estoque total. Lote ignorado."
                        )
                        continue
                    
                    # Limita a quantidade ao disponível
                    qtd_final = min(qtd_solicitada, qtd_restante)
                    
                    if qtd_final < qtd_solicitada:
                        self.warnings.append(
                            f"Linha {linha}: SKU '{codigo_sku}' - Quantidade ajustada de {qtd_solicitada} para {qtd_final} (limite do estoque)."
                        )
                    
                    # Gera número de lote baseado na validade
                    numero_lote = f"VAL_{data_validade.strftime('%Y%m%d')}"
                    
                    # Busca ou cria Lote com validade
                    lote, lote_created = LoteValidade.objects.get_or_create(
                        sku=sku,
                        data_validade=data_validade,
                        defaults={
                            'numero_lote': numero_lote,
                            'qtd_estoque': qtd_final,
                        }
                    )
                    
                    if not lote_created:
                        lote.qtd_estoque = qtd_final
                        lote.numero_lote = numero_lote
                        lote.save()
                        self.updated_count += 1
                    else:
                        self.created_count += 1
                    
                    soma_novos_lotes += qtd_final
                    self.processed_count += 1
                
                # Recalcula o lote BASE (estoque cego)
                soma_todos_lotes_validade = LoteValidade.objects.filter(
                    sku=sku,
                    ativo=True,
                    data_validade__isnull=False
                ).aggregate(
                    total=Sum('qtd_estoque')
                )['total'] or 0
                
                estoque_cego = total_disponivel - soma_todos_lotes_validade
                lote_base.qtd_estoque = max(0, estoque_cego)
                lote_base.save()
            
            return self._build_result('Contagens')
            
        except Exception as e:
            return {
                'success': False,
                'error': str(e),
                'processed': 0,
            }
    
    def _reset_counters(self):
        """Reseta contadores para novo processamento."""
        self.errors = []
        self.warnings = []
        self.processed_count = 0
        self.created_count = 0
        self.updated_count = 0
    
    def _build_result(self, tipo: str) -> Dict[str, Any]:
        """Constrói dicionário de resultado."""
        return {
            'success': len(self.errors) == 0 or self.processed_count > 0,
            'tipo': tipo,
            'unidade': str(self.unidade_negocio),
            'processed': self.processed_count,
            'created': self.created_count,
            'updated': self.updated_count,
            'errors': self.errors,
            'warnings': self.warnings,
            'timestamp': timezone.now().isoformat(),
        }
