unit Face_Metric_ResNet_TrainAPIDemoFrm;

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
      // AI����
      ai: TAI;
      param: PMetric_ResNet_Train_Parameter;
      imgMat: TAI_ImageMatrix;
      successed: Boolean;
    begin
      TThread.Synchronize(Sender, procedure
        begin
          fn := umlCombineFileName(TPath.GetLibraryPath, FileEdit.Text);
        end);

      // imgMat��ͼƬ�������ڴ�����ģͼƬ���ݼ���ѵ��
      imgMat := TAI_ImageMatrix.Create;

      // ����ͼƬ�����ڶ�ȡ�ͱ������ͼƬ���ǳ�����һ����˵��һ�ζ�ȡ�ͱ��涼����ʮ���ţ�����Ĳ���Ҫ����
      // ͼƬ����ı���Ͷ�ȡ�����ǲ��л��ģ��Ὣcpu������Ȼ���ô���IO�����ɹ������Լ��ٵȴ�ʱ��
      imgMat.LoadFromFile(fn);

      // ����zAI������
      // zAI����������߳���ֱ�ӹ���������Sync
      ai := TAI.OpenEngine();

      DoStatus('��ʼѵ��');
      // ��ʼѵ��ͼƬ�����
      // ����ѵ�����ģ����ʱ����Ӧ��ѡ��ͼƬ����ʽ��ѵ��
      param := TAI.Init_Metric_ResNet_Parameter(umlChangeFileExt(fn, '.sync'), umlChangeFileExt(fn, C_Metric_ResNet_Ext));

      // ���μƻ�ѵ��3Сʱ
      // ��3Сʱ��������ʱ�������϶�û�дﵽҪ�󽫻�ǿ���˳�
      // ǿ���˳��ĳ���������϶������ֵ�������������������
      // AI.Last_training_average_loss, AI.Last_training_learning_rate: Double;
      // �����3Сʱ�ڳ����˳��ģ��ͱ�ʾ���������Ҫ��
      param^.timeout := C_Tick_Hour * 3;

      // ������������100
      param^.iterations_without_progress_threshold := 100;

      // resnet���ѧϰ����
      // resnet����ÿ�������ѧϰ��step�У���mini batch��С���Σ���������ǣ��������ݣ���ÿ��step������в�һ�������ֿ�����ϵ�face����
      // step_mini_batch_target_num��ͬ����ʵ��������������ʱ����϶�ѧϰ������������õ�
      // ��������gpu�������ڴ����ƣ�step_mini_batch_target_num���Ѵﵽ�ǳ������������ˣ�������Ҫstep�����������Ĳü���������
      // �������ÿ��step������100�������face���Σ������ֵ���������úõ��ڴ��������������gpu�ڴ�������ڴ棩
      // ����ڴ����õ�128G+4��sli�������ֵ����д500
      // ���ߵ�����Ϊ12G�Դ棬16G���������ڴ棬�����ֵ��д��100����ѧϰ�����У��������ƽ�Ӳ������
      // ����step_mini_batch_target_num��ֵ���󣬻����С��zAI�ں˻��Զ�������ֵ�������ʱ�򣬲���Ҫר�Ŷ����趨
      // ������ѵ���ܴ�����ݼ�ʱ��Ҳ�����ǲ���һ����ɣ�������Ҫ�޸����ݼ��Ժ󷴸�ѵ����������Щֵ�Ż���Ҫ�̶�����
      param^.step_mini_batch_target_num := 100;

      // resnet���ѧϰ������ÿ��step����ʱ����ÿ��face�������Ĺ�դ���������������ֵ���������úõ��ڴ��������������gpu�ڴ�������ڴ棩
      // ����ڴ����õ�128G+4��sli�������ֵ����д20���ϣ������ֵ��д��5����ѧϰ�����У��������ƽ�Ӳ������
      // ����step_mini_batch_raster_num��ֵ���󣬻����С��zAI�ں˻��Զ�������ֵ�������ʱ�򣬲���Ҫר�Ŷ����趨
      // ������ѵ���ܴ�����ݼ�ʱ��Ҳ�����ǲ���һ����ɣ�������Ҫ�޸����ݼ��Ժ󷴸�ѵ����������Щֵ�Ż���Ҫ�̶�����
      param^.step_mini_batch_raster_num := 5;

      // ���ѧϰ�����й����е��ر�˵����
      // zAI�����ѧϰ�Ĺ����У�ÿ��5���ӻᱣ��һ��״̬�ļ�
      // ����������崻��������Ժ󣬿��Դ������һ��״̬�ļ��лָ�
      // �ָ�ֻ��Ҫ���µ㿪����ֻҪ��֤ѵ���������������������

      // ���ѧϰ�������Ż�������ر�˵����
      // ��Ϊרҵѧϰ���ǳ��������4��������һ̨���ѧϰ���������豸Ͷ����ʮ�����϶��Ǻ�ƽ����
      // �������Կ�һ�����ñȽϵͣ����׷��ȣ��ڴ������Ҳ�ܸߣ���ؼ��Ļ���������ѵ���У����ǻ��Ṥ����������ѵ��Ӱ��̫�๤��
      // �������Ͽ��ǣ������ɵ�cuda������Ʋ�������õ�cuda���ƣ��µ�Metric_ResNet_Trainѧϰ���ƿ��Բ��ú���ʽѧϰ
      // ����ʽѧϰ��ѧϰЧ����������ɻ��20%����ÿ�ε���������gpu���ݺ���һ�£�������һ���Դ���ڴ���֤����
      // ����ʽѧϰ�����ʺϴ��ģ�ͳ�ʱ������ݼ�ѵ���������ʺ����ã���������Ҫ������ʱ��ѵ��ģ��

      // ������GPUѵ��������رգ����Ǻ���ʽѵ��
      // ����������ò��ã�������Ҫ��������+ѵ��ͬ�����У�����ر�
      // ����������sli or fire�������
      // ��Ϊ�ҵ�����ƫ�иߣ����������Ǵ�״̬
      param^.fullGPU_Training := True;

      // ���ˣ����ǿ�ʼִ�ж������Ĳв�����ѵ����
      successed := ai.Metric_ResNet_Train(imgMat, param);

      TAI.Free_Metric_ResNet_Parameter(param);

      if successed then
        begin
          DoStatus('ѵ���ɹ�.');
        end
      else
          DoStatus('ѵ��ʧ��.');

      // �ͷ�ѵ��ʹ�õ�����
      DisposeObject(ai);
      DisposeObject(imgMat);
    end);
end;

end.
