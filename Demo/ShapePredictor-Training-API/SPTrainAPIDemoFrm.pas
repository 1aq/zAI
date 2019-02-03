unit SPTrainAPIDemoFrm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,

  System.IOUtils, Vcl.ExtCtrls,

  CoreClasses, PascalStrings, UnicodeMixedLib, zAI, zAI_Common, zAI_TrainingTask,
  ListEngine, zDrawEngineInterface_SlowFMX, MemoryRaster, DoStatusIO, MemoryStream64;

type
  TForm2 = class(TForm)
    Memo1: TMemo;
    FileEdit: TLabeledEdit;
    trainingButton: TButton;
    SaveDialog: TSaveDialog;
    Timer1: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure trainingButtonClick(Sender: TObject);
  private
    { Private declarations }
    procedure DoStatusMethod(AText: SystemString; const ID: Integer);
  public
    { Public declarations }
  end;

var
  Form2: TForm2;

implementation

{$R *.dfm}


procedure TForm2.DoStatusMethod(AText: SystemString; const ID: Integer);
begin
  Memo1.Lines.Add(AText);
end;

procedure TForm2.FormCreate(Sender: TObject);
begin
  AddDoStatusHook(Self, DoStatusMethod);
  // ��ȡzAI������
  ReadAIConfig;
  // ��һ��������Key����������֤ZAI��Key
  // ���ӷ�������֤Key������������ʱһ���Ե���֤��ֻ�ᵱ��������ʱ�Ż���֤��������֤����ͨ����zAI����ܾ�����
  // �ڳ��������У���������TAI�����ᷢ��Զ����֤
  // ��֤��Ҫһ��userKey��ͨ��userkey�����ZAI������ʱ���ɵ����Key��userkey����ͨ��web���룬Ҳ������ϵ���߷���
  // ��֤key���ǿ����Ӽ����޷����ƽ�
  zAI.Prepare_AI_Engine();
end;

procedure TForm2.Timer1Timer(Sender: TObject);
begin
  // dostatus������������ˢ�����߳��е�StatusIO״̬������ˢ��parallel�߳��е�status
  DoStatus;
end;

procedure TForm2.trainingButtonClick(Sender: TObject);
begin
  TComputeThread.RunP(nil, nil,
    procedure(Sender: TComputeThread)
    var
      fn: U_String;
      ai: TAI;
      dt: TTimeTick;
      imgList: TAI_ImageList;
      m64: TMemoryStream64;
    begin
      TThread.Synchronize(Sender, procedure
        begin
          fn := umlCombineFileName(TPath.GetLibraryPath, FileEdit.Text);
        end);

      imgList := TAI_ImageList.Create;
      imgList.LoadFromFile(fn);
      DoStatus('�������ݼ��ߴ�');
      imgList.Scale(0.5);
      ai := TAI.OpenEngine();
      DoStatus('��ʼѵ��');
      dt := GetTimeTick();
      m64 := ai.SP_Train_Stream(imgList, 300, 3, 8);
      if m64 <> nil then
        begin
          DoStatus('ѵ���ɹ�.��ʱ %d ����', [GetTimeTick() - dt]);
          TThread.Synchronize(Sender, procedure
            begin
              SaveDialog.FileName := 'output' + zAI.C_SP_Ext;
              SaveDialog.DefaultExt := zAI.C_SP_Ext;
              SaveDialog.Filter := Format('%s|*%s', [zAI.C_SP_Ext, zAI.C_SP_Ext]);
              if not SaveDialog.Execute() then
                  exit;
              m64.SaveToFile(SaveDialog.FileName);
            end);
          DisposeObject(m64);
        end
      else
          DoStatus('ѵ��ʧ��.');
      DisposeObject(ai);
      DisposeObject(imgList);
    end);
end;

end.
