import pandas as pd
from io import BytesIO
from datetime import datetime
import logging
from django.db import transaction

from core.models import SKU, UnidadeNegocio

logger = logging.getLogger(__name__)

# =============================================================================
# REGRAS DE CLASSIFICAÇÃO POR CATEGORIA
# =============================================================================
REGRAS_CATEGORIA = {
    'CERVEJA': [
        'SKOL', 'BRAHMA', 'ANTARCTICA PILSEN', 'ANTARCTICA SUBZERO', 
        'ORIGINAL', 'BUDWEISER', 'MICHELOB', 'CORONA', 'CORONITA', 
        'STELLA', 'SPATEN', 'BOHEMIA', 'MALZBIER'
    ],
    'REFRIGERANTE': ['GUARANA', 'PEPSI', 'SUKITA', 'SODA', 'H2OH', 'TONICA'],
    'BEATS': ['BEATS'],
    'ICE E MISTAS': ['ICE'],
    'ÁGUA': ['INDAIA', 'PETROPOLIS AGUA', 'AGUA MIN'],
    'SUCO': ['TIAL', 'TANG'],
    'ISOTÔNICO': ['GATORADE'],
    'ENERGÉTICO': ['RED BULL'],
    'DESTILADO': [
        'JOHNNIE WALKER', 'ABSOLUT', 'SMIRNOFF ORIGINAL', 'MONTILLA', 
        'BALLANTINES', 'PIRASSUNUNGA', 'PASSPORT', 'DOMECQ', 'PITU', 'WHISKY'
    ],
    'VINHO': ['QUINTA DO MORGADO', 'VINHO'],
    'DOCES': ['TRIDENT', 'HALLS', 'CHICLETE'],
    'LIMPEZA': ['YPE'],
    'OUTROS': ['GARRAFEIRA', 'CERVEGELA'],
}

ORDEM_CATEGORIAS = [
    'BEATS', 'ICE E MISTAS', 'ÁGUA', 'SUCO',
    'ISOTÔNICO', 'ENERGÉTICO', 'DESTILADO', 'VINHO', 
    'DOCES', 'LIMPEZA', 'REFRIGERANTE', 'OUTROS', 'CERVEJA'
]

def parse_disponivel(disponivel_str, fator_conversao: int) -> int:
    """Converte a string "Caixas/Unidades" para Unidades Base."""
    if pd.isna(disponivel_str):
        return 0
    if isinstance(disponivel_str, (int, float)):
        return int(disponivel_str)
        
    disponivel_str = str(disponivel_str).strip()
    if not disponivel_str:
        return 0
    
    if '/' in disponivel_str:
        partes = disponivel_str.split('/')
        try:
            caixas = int(partes[0].replace('.', ''))
            unidades = int(partes[1])
            return caixas * (fator_conversao or 1) + unidades
        except ValueError:
            return 0
    else:
        try:
            return int(float(disponivel_str))
        except ValueError:
            return int(disponivel_str.replace('.', ''))

class UploadFefoService:
    @classmethod
    def _classificar_categoria(cls, nome_produto: str) -> str:
        """Classifica o produto baseado no dicionário de regras."""
        if not nome_produto:
            return 'OUTROS'
        nome_upper = str(nome_produto).upper()
        
        for cat in ORDEM_CATEGORIAS:
            palavras_chave = REGRAS_CATEGORIA.get(cat, [])
            for palavra in palavras_chave:
                if palavra in nome_upper:
                    return cat
        return 'OUTROS'

    @staticmethod
    @transaction.atomic
    def processar_estoque_fefo(file_020502, file_020304, file_nri, unidade_negocio_id: int):
        try:
            unidade = UnidadeNegocio.objects.get(id=unidade_negocio_id)
        except UnidadeNegocio.DoesNotExist:
            raise ValueError("Unidade de negócio não encontrada.")

        # Leitura dos arquivos
        try:
            df_020502 = UploadFefoService._read_file(file_020502)
            df_020304 = UploadFefoService._read_file(file_020304)
            df_nri = UploadFefoService._read_file(file_nri)
        except Exception as e:
            raise ValueError(f"Erro ao ler os arquivos: {e}")

        # Limpeza de cabeçalhos
        df_020502.columns = df_020502.columns.str.strip()
        df_020304.columns = df_020304.columns.str.strip()
        df_nri.columns = df_nri.columns.str.strip()

        # Mapeamento dinâmico de colunas
        col_prod_020502 = next((c for c in df_020502.columns if c.lower() in ['produto', 'material', 'cod']), 'Produto')
        col_cod_020304 = next((c for c in df_020304.columns if c.lower() in ['cod', 'material', 'produto']), 'Cod')
        col_cod_nri = next((c for c in df_nri.columns if c.lower() in ['código produto', 'codigo', 'material']), 'Código Produto')
        
        col_desc_020502 = next((c for c in df_020502.columns if c.lower() in ['descrição', 'descricao', 'nome', 'texto', 'material_desc']), None)
        col_uom_020502 = next((c for c in df_020502.columns if c.lower() in ['unidade', 'unid', 'unid.', 'un', 'umed']), None)
        col_fator_020502 = next((c for c in df_020502.columns if c.lower() in ['fator', 'fator conv', 'fator de conversão', 'conversão', 'conversao']), None)

        df_020502['Produto_clean'] = df_020502.get(col_prod_020502, pd.Series()).astype(str).str.replace(r'\.0$', '', regex=True).str.lstrip('0').str.strip()
        df_020304['Cod_clean'] = df_020304.get(col_cod_020304, pd.Series()).astype(str).str.replace(r'\.0$', '', regex=True).str.lstrip('0').str.strip()
        df_nri['Codigo_clean'] = df_nri.get(col_cod_nri, pd.Series()).astype(str).str.replace(r'\.0$', '', regex=True).str.lstrip('0').str.strip()
        
        if 'Data Validade' in df_nri.columns:
            df_nri['Data Validade'] = pd.to_datetime(df_nri['Data Validade'], dayfirst=True, errors='coerce')
        if 'Quantidade' in df_nri.columns:
            df_nri['Quantidade'] = pd.to_numeric(df_nri['Quantidade'], errors='coerce').fillna(0)

        # "Zona de Perigo" Automática: Zera tudo antes de processar o novo estoque
        SKU.objects.filter(unidade_negocio=unidade).update(
            qtd_total_020502=0,
            qtd_buffer_020304=0,
            qtd_disponivel_venda=0,
            validade_inicio_range=None,
            validade_fim_range=None
        )

        skus_dict = {
            sku.codigo_sku: sku
            for sku in SKU.objects.filter(unidade_negocio=unidade)
        }
        
        skus_to_update = []
        hoje = datetime.now().date()

        for idx, row_020502 in df_020502.iterrows():
            cod_sku = row_020502.get('Produto_clean')
            if not cod_sku or pd.isna(cod_sku) or cod_sku.lower() == 'nan':
                continue

            # Extração segura do Fator de Conversão da linha atual
            fator_val = 1
            if col_fator_020502:
                raw_fator = row_020502.get(col_fator_020502, 1)
                try:
                    fator_val = int(float(raw_fator))
                    if fator_val <= 0:
                        fator_val = 1
                except (ValueError, TypeError):
                    fator_val = 1

            sku = skus_dict.get(cod_sku)
            
            # 1. AUTO-CADASTRO (COM FATOR E UNIDADE DE MEDIDA)
            if not sku:
                nome_prod = str(row_020502.get(col_desc_020502, f"SKU {cod_sku}")) if col_desc_020502 else f"SKU {cod_sku}"
                
                # Trata Unidade de Medida
                uom_val = 'UN'
                if col_uom_020502:
                    raw_uom = str(row_020502.get(col_uom_020502, 'UN')).strip().upper()
                    if raw_uom and raw_uom != 'NAN':
                        uom_val = raw_uom[:3]

                categoria_classificada = UploadFefoService._classificar_categoria(nome_prod)

                sku = SKU.objects.create(
                    codigo_sku=cod_sku,
                    nome_produto=nome_prod[:255],
                    unidade_negocio=unidade,
                    fator_conversao=fator_val,
                    unidade_medida=uom_val,
                    categoria=categoria_classificada,
                    ativo=True
                )
                skus_dict[cod_sku] = sku
            else:
                # AUTO-CORREÇÃO: Atualiza o fator de conversão de SKUs existentes se estiver diferente
                if sku.fator_conversao != fator_val:
                    sku.fator_conversao = fator_val

            # 2. MATEMÁTICA GERENCIAL DE ESTOQUE
            str_disponivel = row_020502.get('Disponivel', '0/0')
            qtd_total = parse_disponivel(str_disponivel, sku.fator_conversao)

            row_020304 = df_020304[df_020304['Cod_clean'] == cod_sku]
            qtd_buffer = 0
            if not row_020304.empty:
                col_saida = 'Saidas' if 'Saidas' in row_020304.columns else ('Saída' if 'Saída' in row_020304.columns else None)
                if col_saida:
                    qtd_buffer = pd.to_numeric(row_020304[col_saida], errors='coerce').fillna(0).sum()
                    qtd_buffer = int(qtd_buffer)

            qtd_disponivel = qtd_total - qtd_buffer
            
            if qtd_disponivel <= 0:
                sku.qtd_total_020502 = qtd_total
                sku.qtd_buffer_020304 = qtd_buffer
                sku.qtd_disponivel_venda = 0
                skus_to_update.append(sku)
                continue

            # 3. MOTOR FEFO REVERSO COM FILTRO DE VENCIDOS
            df_nri_item = df_nri[(df_nri['Codigo_clean'] == cod_sku) & (df_nri['Data Validade'].notna())]
            df_nri_item = df_nri_item.sort_values(by='Data Validade', ascending=True)

            validade_inicio_valida = None
            validade_fim_valida = None
            qtd_vencida = 0

            if not df_nri_item.empty:
                sum_nri = df_nri_item['Quantidade'].sum()
                qtd_queimada = sum_nri - qtd_disponivel

                restante_para_queimar = qtd_queimada if qtd_queimada > 0 else 0

                for _, row_nri in df_nri_item.iterrows():
                    qtd_linha = row_nri['Quantidade']
                    data_val = row_nri['Data Validade'].date()

                    if restante_para_queimar >= qtd_linha:
                        restante_para_queimar -= qtd_linha
                        continue

                    qtd_sobrou_nesta_linha = qtd_linha - restante_para_queimar
                    restante_para_queimar = 0 

                    if data_val < hoje:
                        qtd_vencida += qtd_sobrou_nesta_linha
                    else:
                        if validade_inicio_valida is None:
                            validade_inicio_valida = data_val
                        validade_fim_valida = data_val
            
            qtd_disponivel_venda_real = qtd_disponivel - qtd_vencida
            if qtd_disponivel_venda_real < 0:
                qtd_disponivel_venda_real = 0

            # 4. ATUALIZAÇÃO FINAL
            sku.qtd_total_020502 = qtd_total
            sku.qtd_buffer_020304 = qtd_buffer
            sku.qtd_disponivel_venda = int(qtd_disponivel_venda_real)
            sku.validade_inicio_range = validade_inicio_valida
            sku.validade_fim_range = validade_fim_valida
            skus_to_update.append(sku)

        if skus_to_update:
            # Adicionado o fator_conversao ao bulk_update para salvar possíveis alterações
            SKU.objects.bulk_update(
                skus_to_update, 
                ['qtd_total_020502', 'qtd_buffer_020304', 'qtd_disponivel_venda', 'validade_inicio_range', 'validade_fim_range', 'fator_conversao']
            )

        return {
            'success': True,
            'skus_atualizados': len(skus_to_update)
        }

    @staticmethod
    def _read_file(file) -> pd.DataFrame:
        filename = file.name.lower()
        if filename.endswith('.csv'):
            for encoding in ['utf-8', 'latin-1', 'cp1252']:
                for sep in [';', ',', '\t', '|']:
                    try:
                        file.seek(0)
                        df = pd.read_csv(file, encoding=encoding, sep=sep)
                        if len(df.columns) > 1:
                            return df
                    except Exception:
                        continue
            raise ValueError(f"Não foi possível processar o CSV: {filename}. Verifique a formatação.")
        else:
            file.seek(0)
            return pd.read_excel(file)