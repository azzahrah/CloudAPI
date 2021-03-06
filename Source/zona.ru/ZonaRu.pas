{***************************************************************************}
{                                                                           }
{           CloudApi for Delphi                                             }
{                                                                           }
{           Copyright (c) 2014-2018 Maxim Sysoev                            }
{                                                                           }
{           https://t.me/CloudAPI                                           }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Licensed under the Apache License, Version 2.0 (the "License");          }
{  you may not use this file except in compliance with the License.         }
{  You may obtain a copy of the License at                                  }
{                                                                           }
{      http://www.apache.org/licenses/LICENSE-2.0                           }
{                                                                           }
{  Unless required by applicable law or agreed to in writing, software      }
{  distributed under the License is distributed on an "AS IS" BASIS,        }
{  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. }
{  See the License for the specific language governing permissions and      }
{  limitations under the License.                                           }
{                                                                           }
{***************************************************************************}

unit ZonaRu;

interface

uses
  System.Classes,
  CloudAPI.BaseComponent,
  ZonaRu.Query,
  ZonaRu.Types;

type
  TZona = class(TCloudApiBaseComponent)
  private
    FQuery: TZonaQuery;
    FLastResponse: IznLastResponse;
  protected
    function ExractDocs(const AInput: string): string;
    procedure DoInitApiCore; override;
  protected
    function GetMedia(const AStart, ARows: Integer): TArray<IznCoverFilm>;
  public
    function LastResponse: IznLastResponse;
    function GetMovies(const AStart, ARows: Integer): TArray<IznCoverFilm>;
    function GetSerials(const AStart, ARows: Integer): TArray<IznCoverFilm>;
    function OpenMedia(const ID: Integer): IznItemFull;
    function DirectMediaInfo(const ID: IznItemFull): IznDirectMediaInfo;
    destructor Destroy; override;
    constructor Create(AOwner: TComponent); override;
  end;

implementation

uses
  CloudAPI.Request,
  CloudAPI.Utils.JSON,
  System.SysUtils,
  System.JSON;
{ TZona }

constructor TZona.Create(AOwner: TComponent);
begin
  inherited;
  FQuery := TZonaQuery.Create;
end;

destructor TZona.Destroy;
begin
  FQuery.Free;
  inherited;
end;

function TZona.DirectMediaInfo(const ID: IznItemFull): IznDirectMediaInfo;
var
  LResp: string;
begin
  LResp := GetRequest.HttpClient.Get('https://w6.zona.plus/ajax/video/' + ID.mobi_link_id.ToString).ContentAsString();
  Result := TznDirectMediaInfo.Create(LResp);
end;

procedure TZona.DoInitApiCore;
begin
  inherited;
  Domain := 'http://zsolr3.zonasearch.com/solr';
  GetRequest.StoreAutoFormat := TStoreFormat.InUrl;
  GetRequest.OnStaticFill :=
    procedure
    begin
      with GetRequest do
      begin
        AddParameter('Accept', 'text/html, image/gif, image/jpeg, *; q=.2, */*; q=.2', '', True, TStoreFormat.InHeader);
        AddParameter('Accept-Encoding', 'gzip, deflate', '', True, TStoreFormat.InHeader);
        AddParameter('Connection', 'keep-alive', '', True, TStoreFormat.InHeader);
        AddParameter('User-Agent', 'Java/1.8.0_171', '', True, TStoreFormat.InHeader);
        AddParameter('version', '2.2', '', True);
        AddParameter('wt', 'json', '', True);
      end;

    end;
  GetRequest.OnDataReceiveAsString :=
    function(AInput: string): string
    var
      LJSON: TJSONObject;
    begin
      if Assigned(OnReceiveRawData) then
        OnReceiveRawData(Self, AInput);
      Result := '';
      if AInput.IsEmpty or AInput.StartsWith('<html') then
        Exit;
      LJSON := TJSONObject.ParseJSONValue(AInput) as TJSONObject;
      try
        Result := LJSON.GetValue('response').ToString;
        FLastResponse := TznLastResponse.Create(result);
      finally
        LJSON.Free;
      end;
    end;
  GetRequest.OnDataSend :=
    procedure(AUrl, AData, AHeaders: string)
    begin
      if Assigned(OnSendData) then
        OnSendData(Self, AUrl, AData);
    end;
end;

function TZona.ExractDocs(const AInput: string): string;
var
  LJSON: TJSONObject;
begin
  Result := '';
  LJSON := TJSONObject.ParseJSONValue(AInput) as TJSONObject;
  try
    Result := LJSON.GetValue('docs').ToString;
  finally
    LJSON.Free;
  end;
end;

function TZona.GetMedia(const AStart, ARows: Integer): TArray<IznCoverFilm>;
const
  // CQ = '(NOT(abuse:zona)AND(adult:false)AND(tor_count:[1+TO+2147483647])AND(indexed:[1+TO+7])AND(serial:false)NOT(genreId:(12+OR+15+OR+25+OR+26+OR+1747+OR+28+OR+27+OR+tv)))';
  CFL1 =
    'id,year,playable,trailer,quality,audio_quality,type3d,serial,languages_imdb,rating,genre,runtime,episodes,tor_count,serial_end_year,serial_ended,abuse,';
  CFL2 =
    'release_date_int,release_date_rus,indexed,geo_rules,partner_entity_id,partner_type,name_rus,name_ukr,name_eng,name_original';
  CFL = CFL1 + CFL2;
var
  LResp: string;
begin
  with GetRequest do
  begin
    SetMethod('movie/select');
    AddParameter('q', FQuery.ToCatalog, '', True);
    AddParameter('sort', 'popularity desc,seeds desc,id desc', '', True);
    AddParameter('fl', CFL, '', True);
    AddParameter('start', AStart, -1, True);
    AddParameter('rows', ARows, -1, True);
    LResp := (ExractDocs(ExecuteAsString));
    Result := TBaseJson.AsArray<IznCoverFilm>(TznCoverFilm, LResp);
  end;
end;

function TZona.GetMovies(const AStart, ARows: Integer): TArray<IznCoverFilm>;
begin
  FQuery.Serial := False;
  Result := GetMedia(AStart, ARows);
end;

function TZona.GetSerials(const AStart, ARows: Integer): TArray<IznCoverFilm>;
begin
  FQuery.Serial := True;
  Result := GetMedia(AStart, ARows);
end;

function TZona.LastResponse: IznLastResponse;
begin
  Result := FLastResponse;
end;

function TZona.OpenMedia(const ID: Integer): IznItemFull;
var
  LResp: string;
begin
  FQuery.ID := ID;
  with GetRequest do
  begin
    SetMethod('movie/select');
    AddParameter('q', FQuery.ToItem, '', True);
    AddParameter('start', 0, -1, True);
    AddParameter('rows', 1, -1, True);
    LResp := (ExractDocs(ExecuteAsString));
    Result := TBaseJson.AsArray<IznItemFull>(TznItemFull, LResp)[0];
  end;
end;

end.

